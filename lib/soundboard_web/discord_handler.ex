defmodule SoundboardWeb.DiscordHandler do
  @moduledoc """
  Handles the Discord events.
  """
  @behaviour Nostrum.Consumer
  require Logger

  alias Nostrum.Api.{Message, Self}
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Voice
  alias Soundboard.{Accounts.User, Repo, Sound, UserSoundSetting}
  import Ecto.Query

  # State GenServer
  defmodule State do
    @moduledoc """
    Handles the state of the Discord handler.
    """
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def init(_) do
      {:ok, %{voice_states: %{}}}
    end

    def get_state(user_id) do
      GenServer.call(__MODULE__, {:get_state, user_id})
    rescue
      _ -> nil
    end

    def update_state(user_id, channel_id, session_id) do
      GenServer.cast(__MODULE__, {:update_state, user_id, channel_id, session_id})
    rescue
      _ -> :error
    end

    def handle_call({:get_state, user_id}, _from, state) do
      {:reply, Map.get(state.voice_states, user_id), state}
    end

    def handle_cast({:update_state, user_id, channel_id, session_id}, state) do
      {:noreply,
       %{state | voice_states: Map.put(state.voice_states, user_id, {channel_id, session_id})}}
    end
  end

  def init do
    Logger.info("Starting DiscordHandler...")
    if not auto_join_disabled?(), do: start_guild_check_task()
    :ok
  end

  defp start_guild_check_task do
    Task.start(fn ->
      Logger.info("Starting voice channel check task...")
      Process.sleep(5000)
      check_guilds()
    end)
  end

  defp check_guilds do
    case Enum.to_list(GuildCache.all()) do
      [] -> Logger.warning("No guilds found in cache. Discord may not be ready.")
      guilds -> process_guilds(guilds)
    end
  end

  defp process_guilds(guilds) do
    guilds = Enum.to_list(guilds)
    Logger.info("Found #{length(guilds)} guilds")

    for guild <- guilds do
      Logger.info("Checking guild #{guild.id} for voice channels...")
      check_and_join_voice(guild)
    end
  end

  # Add helper function for leaving voice channel
  defp leave_voice_channel(guild_id) do
    if connected_to_discord?() do
      Logger.info("Bot leaving voice channel in guild #{guild_id}")
      Process.delete(:current_voice_channel)

      # Add rate limit protection
      try do
        Voice.leave_channel(guild_id)
      rescue
        e ->
          error_msg = Exception.message(e)
          Logger.error("Error leaving voice channel: #{error_msg}")

          # If rate limited, retry after delay
          if is_binary(error_msg) and String.contains?(error_msg, "rate limit") do
            Logger.warning(
              "Rate limited while trying to leave voice channel, retrying in 5 seconds..."
            )

            Process.sleep(5000)
            Voice.leave_channel(guild_id)
          end
      end

      # Update AudioPlayer
      GenServer.cast(
        SoundboardWeb.AudioPlayer,
        {:set_voice_channel, nil, nil}
      )
    else
      Logger.warning("Skipping leave_voice_channel - not connected to Discord")
    end
  end

  # Add helper function for joining voice channel
  defp join_voice_channel(guild_id, channel_id) do
    if connected_to_discord?() do
      Logger.info("Bot joining voice channel #{channel_id} in guild #{guild_id}")
      Process.put(:current_voice_channel, {guild_id, channel_id})

      # Add rate limit protection
      try do
        Voice.join_channel(guild_id, channel_id)
      rescue
        e ->
          error_msg = Exception.message(e)
          Logger.error("Error joining voice channel: #{error_msg}")

          # If rate limited, retry after delay
          if is_binary(error_msg) and String.contains?(error_msg, "rate limit") do
            Logger.warning(
              "Rate limited while trying to join voice channel, retrying in 5 seconds..."
            )

            Process.sleep(5000)
            Voice.join_channel(guild_id, channel_id)
          end
      end

      # Update AudioPlayer
      GenServer.cast(
        SoundboardWeb.AudioPlayer,
        {:set_voice_channel, guild_id, channel_id}
      )
    else
      Logger.warning("Skipping join_voice_channel - not connected to Discord")
    end
  end

  # Add this helper function to check Discord connection state
  defp connected_to_discord? do
    # Check if bot has received READY event
    ready = :persistent_term.get(:soundboard_bot_ready, false)

    if ready do
      try do
        case Self.get() do
          {:ok, _} ->
            Logger.debug("Discord connection check: Connected and ready")
            true

          error ->
            Logger.debug("Discord connection check failed: #{inspect(error)}")
            false
        end
      rescue
        error ->
          Logger.debug("Discord connection check error: #{inspect(error)}")
          false
      end
    else
      Logger.debug("Discord connection check: Bot not ready (READY event not received)")
      false
    end
  end

  # Simplified check_users_in_voice function - no bot token needed
  defp check_users_in_voice(guild_id, channel_id) do
    guild = GuildCache.get!(guild_id)

    # Get bot ID to exclude it from count
    bot_id =
      case Self.get() do
        {:ok, %{id: id}} -> id
        _ -> nil
      end

    # Count total users in the specified channel (excluding the bot)
    users_in_channel =
      guild.voice_states
      |> Enum.count(fn vs ->
        vs.channel_id == channel_id && vs.user_id != bot_id
      end)

    Logger.info("""
    Voice state check:
    Channel ID: #{channel_id}
    Users in channel: #{users_in_channel} (excluding bot)
    Bot ID: #{bot_id}
    Voice states: #{inspect(guild.voice_states)}
    """)

    users_in_channel
  end

  def handle_event({:VOICE_STATE_UPDATE, %{channel_id: nil} = payload, _ws_state}) do
    Logger.info("User #{payload.user_id} disconnected from voice")
    State.update_state(payload.user_id, nil, payload.session_id)

    unless auto_join_disabled?() do
      handle_bot_alone_check(payload.guild_id)
    end

    handle_leave_sound(payload.user_id)
  end

  def handle_event({:VOICE_STATE_UPDATE, payload, _ws_state}) do
    Logger.info("Voice state update received: #{inspect(payload)}")

    # Check if this is the bot's own voice state update
    case Self.get() do
      {:ok, %{id: bot_id}} when bot_id == payload.user_id ->
        Logger.info(
          "BOT VOICE STATE UPDATE - Bot (#{bot_id}) joined channel #{payload.channel_id} in guild #{payload.guild_id}"
        )

      _ ->
        :ok
    end

    previous_state = State.get_state(payload.user_id)
    State.update_state(payload.user_id, payload.channel_id, payload.session_id)

    unless auto_join_disabled?() do
      handle_auto_join_leave(payload)
    end

    handle_join_sound(payload.user_id, previous_state, payload.channel_id)
  end

  def handle_event({:READY, _payload, _ws_state}) do
    Logger.info("Bot is READY - gateway connection established")
    :persistent_term.put(:soundboard_bot_ready, true)
    :noop
  end

  def handle_event({:VOICE_READY, payload, _ws_state}) do
    Logger.info("""
    Voice Ready Event:
    Guild ID: #{payload.guild_id}
    Channel ID: #{payload.channel_id}
    """)

    :noop
  end

  def handle_event({:VOICE_SERVER_UPDATE, _payload, _ws_state}) do
    :noop
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case msg.content do
      "!join" ->
        case get_user_voice_channel(msg.guild_id, msg.author.id) do
          nil ->
            Message.create(msg.channel_id, "You need to be in a voice channel!")

          channel_id ->
            join_voice_channel(msg.guild_id, channel_id)

            # Send web interface URL
            scheme = System.get_env("SCHEME")

            web_url =
              Application.get_env(:soundboard, SoundboardWeb.Endpoint)[:url][:host] || "localhost"

            url = "#{scheme}://#{web_url}"

            Message.create(msg.channel_id, """
            Joined your voice channel!
            Access the soundboard here: #{url}
            """)
        end

      "!leave" ->
        if msg.guild_id do
          leave_voice_channel(msg.guild_id)
          Message.create(msg.channel_id, "Left the voice channel!")
        end

      _ ->
        :ignore
    end
  end

  def handle_event(_event) do
    :noop
  end

  defp get_user_voice_channel(guild_id, user_id) do
    guild = GuildCache.get!(guild_id)

    case Enum.find(guild.voice_states, fn vs -> vs.user_id == user_id end) do
      nil -> nil
      voice_state -> voice_state.channel_id
    end
  end

  # Handle delayed sound playback
  def handle_info({:play_delayed_sound, sound}, state) do
    Logger.info("Playing delayed join sound: #{sound}")
    SoundboardWeb.AudioPlayer.play_sound(sound, "System")
    {:noreply, state}
  end

  # Handle Nostrum events
  def handle_info({:event, {event_name, payload, ws_state}}, state) do
    handle_event({event_name, payload, ws_state})
    {:noreply, state}
  end

  # Catch-all for other info messages
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  def get_current_voice_channel do
    Process.get(:current_voice_channel)
  end

  # Add this helper function
  defp check_and_join_voice(guild) do
    # Get all voice states for the guild
    voice_states = guild.voice_states
    bot_id = Application.get_env(:nostrum, :user_id)

    Logger.info("""
    Checking voice states for guild #{guild.id}:
    Total voice states: #{length(voice_states)}
    Bot ID: #{bot_id}
    Voice states: #{inspect(voice_states)}
    """)

    # Find first channel with users (excluding the bot)
    case Enum.find(voice_states, fn vs ->
           vs.user_id != bot_id && vs.channel_id != nil
         end) do
      %{channel_id: channel_id} = voice_state when not is_nil(channel_id) ->
        Logger.info("""
        Found user in voice channel:
        Channel ID: #{channel_id}
        Voice State: #{inspect(voice_state)}
        Attempting to join...
        """)

        Process.put(:current_voice_channel, {guild.id, channel_id})
        Voice.join_channel(guild.id, channel_id)

        # Update AudioPlayer
        GenServer.cast(
          SoundboardWeb.AudioPlayer,
          {:set_voice_channel, guild.id, channel_id}
        )

      _ ->
        Logger.info("No users found in voice channels for guild #{guild.id}")
    end
  end

  # Add this helper function to check if auto-join is disabled
  defp auto_join_disabled? do
    System.get_env("DISABLE_AUTO_JOIN") == "true"
  end

  defp handle_bot_alone_check(_guild_id) do
    case get_current_voice_channel() do
      {guild_id, channel_id} ->
        check_and_maybe_leave(guild_id, channel_id)

      _ ->
        :noop
    end
  end

  defp check_and_maybe_leave(guild_id, channel_id) do
    users = check_users_in_voice(guild_id, channel_id)

    if users <= 1 do
      Logger.info("Only bot remaining in channel, forcing disconnect")
      leave_voice_channel(guild_id)
    end
  end

  defp handle_auto_join_leave(payload) do
    Logger.info("Handling auto join/leave for payload: #{inspect(payload)}")

    # Check if this is the bot's own voice state update - RETURN EARLY if it is
    case Self.get() do
      {:ok, %{id: bot_id}} when bot_id == payload.user_id ->
        Logger.debug("Ignoring bot's own voice state update in auto-join logic")
        :noop

      _ ->
        process_user_voice_update(payload)
    end
  end

  defp process_user_voice_update(payload) do
    case get_current_voice_channel() do
      nil when payload.channel_id != nil ->
        handle_bot_not_in_voice(payload)

      {guild_id, current_channel_id} when current_channel_id != payload.channel_id ->
        handle_bot_in_different_channel(guild_id, current_channel_id)

      _ ->
        Logger.debug("No action needed for voice state update")
        :noop
    end
  end

  defp handle_bot_not_in_voice(payload) do
    users_in_channel = check_users_in_voice(payload.guild_id, payload.channel_id)
    Logger.info("Found #{users_in_channel} users in channel #{payload.channel_id}")

    if users_in_channel > 0 do
      Logger.info("Joining channel #{payload.channel_id} with #{users_in_channel} users")
      join_voice_channel(payload.guild_id, payload.channel_id)
    end
  end

  defp handle_bot_in_different_channel(guild_id, current_channel_id) do
    users = check_users_in_voice(guild_id, current_channel_id)
    Logger.info("Current channel #{current_channel_id} has #{users} users")

    if users <= 1 do
      Logger.info("Bot is alone in channel #{current_channel_id}, leaving")
      leave_voice_channel(guild_id)
    end
  end

  defp handle_join_sound(user_id, previous_state, new_channel_id) do
    is_join_event =
      case previous_state do
        nil -> true
        {nil, _} -> true
        {prev_channel, _} -> prev_channel != new_channel_id
      end

    if is_join_event do
      play_join_sound(user_id)
    end
  end

  defp play_join_sound(user_id) do
    user_with_sounds =
      from(u in User,
        where: u.discord_id == ^to_string(user_id),
        left_join: uss in UserSoundSetting,
        on: uss.user_id == u.id and uss.is_join_sound == true,
        left_join: s in Sound,
        on: s.id == uss.sound_id,
        select: {u.id, s.filename},
        limit: 1
      )
      |> Repo.one()

    case user_with_sounds do
      {_user_id, join_sound} when not is_nil(join_sound) ->
        Process.send_after(self(), {:play_delayed_sound, join_sound}, 1000)

      _ ->
        :noop
    end
  end

  defp handle_leave_sound(user_id) do
    # Handle leave sound (keep this functionality regardless of auto-join setting)
    user_with_sounds =
      from(u in User,
        where: u.discord_id == ^to_string(user_id),
        left_join: uss in UserSoundSetting,
        on: uss.user_id == u.id and uss.is_leave_sound == true,
        left_join: s in Sound,
        on: s.id == uss.sound_id,
        select: {u.id, s.filename},
        limit: 1
      )
      |> Repo.one()

    case user_with_sounds do
      {_user_id, leave_sound} when not is_nil(leave_sound) ->
        Logger.info("Playing leave sound: #{leave_sound}")
        SoundboardWeb.AudioPlayer.play_sound(leave_sound, "System")

      _ ->
        :noop
    end
  end
end
