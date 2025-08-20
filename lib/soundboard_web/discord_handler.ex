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

      # Clear the AudioPlayer's voice channel
      SoundboardWeb.AudioPlayer.set_voice_channel(nil, nil)

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

      # Update AudioPlayer - set to nil (not {nil, nil})
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

      # Set the AudioPlayer's voice channel so join sounds can play
      SoundboardWeb.AudioPlayer.set_voice_channel(guild_id, channel_id)

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

  # Simplified check_users_in_voice function - safe against cache races
  defp check_users_in_voice(guild_id, channel_id) do
    with true <- is_integer(guild_id),
         true <- not is_nil(channel_id),
         {:ok, guild} <- safe_guild_fetch(guild_id) do
      # Get bot ID to exclude it from count
      bot_id =
        case Self.get() do
          {:ok, %{id: id}} -> id
          _ -> nil
        end

      users_in_channel =
        guild.voice_states
        |> Enum.count(fn vs -> vs.channel_id == channel_id && vs.user_id != bot_id end)

      Logger.info("""
      Voice state check:
      Channel ID: #{channel_id}
      Users in channel: #{users_in_channel} (excluding bot)
      Bot ID: #{bot_id}
      Voice states: #{inspect(guild.voice_states)}
      """)

      users_in_channel
    else
      _ ->
        Logger.warning(
          "check_users_in_voice: cache not ready or invalid target (guild_id=#{inspect(guild_id)}, channel_id=#{inspect(channel_id)})"
        )

        # Non-zero to avoid false positives; a delayed recheck will handle the leave
        1
    end
  end

  defp safe_guild_fetch(guild_id) do
    case GuildCache.get(guild_id) do
      {:ok, guild} -> {:ok, guild}
      _ -> :error
    end
  rescue
    _ -> :error
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

  # New DAVE voice event sometimes surfaced by Nostrum; ignore for now
  def handle_event({:VOICE_CHANNEL_STATUS_UPDATE, _payload, _ws_state}) do
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

  # Handle Nostrum events
  def handle_info({:event, {event_name, payload, ws_state}}, state) do
    handle_event({event_name, payload, ws_state})
    {:noreply, state}
  end

  # Catch-all for other info messages
  def handle_info({:recheck_alone, guild_id, channel_id}, state) do
    case get_current_voice_channel() do
      {gid, cid} when gid == guild_id and cid == channel_id ->
        users = check_users_in_voice(guild_id, channel_id)
        Logger.info("Recheck alone: channel #{channel_id} now has #{users} non-bot users")

        if users == 0 do
          Logger.info("Recheck confirms bot is alone; leaving channel #{channel_id}")
          leave_voice_channel(guild_id)
        end

      _ ->
        Logger.debug("Recheck skipped; voice target changed")
    end

    {:noreply, state}
  end

  # Catch-all for other info messages
  def handle_info(_msg, state), do: {:noreply, state}

  def get_current_voice_channel do
    case Self.get() do
      {:ok, %{id: bot_id}} -> find_bot_voice_channel(bot_id)
      _ -> nil
    end
  end

  defp find_bot_voice_channel(bot_id) do
    case get_cached_guilds() do
      [] -> get_fallback_voice_channel()
      guilds -> find_voice_channel_in_guilds(guilds, bot_id) || get_fallback_voice_channel()
    end
  end

  defp get_cached_guilds do
    case GuildCache.all() do
      nil -> []
      guilds -> guilds
    end
  rescue
    _ -> []
  end

  defp find_voice_channel_in_guilds(guilds, bot_id) do
    Enum.find_value(guilds, fn guild ->
      find_bot_voice_state(guild, bot_id)
    end)
  end

  defp find_bot_voice_state(guild, bot_id) do
    voice_states = guild.voice_states || []

    case Enum.find(voice_states, fn vs -> vs.user_id == bot_id end) do
      %{channel_id: channel_id} when not is_nil(channel_id) -> {guild.id, channel_id}
      _ -> nil
    end
  end

  defp get_fallback_voice_channel do
    candidate =
      case safe_audio_player_voice_channel() do
        nil -> Process.get(:current_voice_channel)
        other -> other
      end

    case candidate do
      {gid, cid} when is_integer(gid) and not is_nil(cid) -> {gid, cid}
      _ -> nil
    end
  end

  defp safe_audio_player_voice_channel do
    SoundboardWeb.AudioPlayer.current_voice_channel()
  catch
    :exit, _ -> nil
    :error, _ -> nil
    _ -> nil
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

  defp check_and_maybe_leave(guild_id, channel_id)
       when is_integer(guild_id) and not is_nil(channel_id) do
    users = check_users_in_voice(guild_id, channel_id)

    if users == 0 do
      Logger.info("No non-bot users remaining in channel, leaving now")
      leave_voice_channel(guild_id)
    else
      # GuildCache may lag briefly after a VOICE_STATE_UPDATE; recheck shortly
      Logger.info("Non-bot users detected (#{users}); scheduling recheck in 1.5s")
      Process.send_after(self(), {:recheck_alone, guild_id, channel_id}, 1_500)
      :noop
    end
  end

  defp check_and_maybe_leave(guild_id, channel_id) do
    Logger.debug(
      "Skipping check_and_maybe_leave due to invalid target: guild_id=#{inspect(guild_id)}, channel_id=#{inspect(channel_id)}"
    )

    :noop
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
      # Check if bot is actually already in this channel (Voice.ready? check)
      if Voice.ready?(payload.guild_id) do
        Logger.debug("Bot already connected to voice in guild #{payload.guild_id}, skipping join")
      else
        Logger.info("Joining channel #{payload.channel_id} with #{users_in_channel} users")
        join_voice_channel(payload.guild_id, payload.channel_id)
      end
    end
  end

  defp handle_bot_in_different_channel(guild_id, current_channel_id)
       when is_integer(guild_id) and not is_nil(current_channel_id) do
    users = check_users_in_voice(guild_id, current_channel_id)
    Logger.info("Current channel #{current_channel_id} has #{users} users")

    if users == 0 do
      Logger.info("Bot is alone in channel #{current_channel_id}, leaving")
      leave_voice_channel(guild_id)
    else
      # Recheck shortly to avoid cache staleness keeping the bot around
      Process.send_after(self(), {:recheck_alone, guild_id, current_channel_id}, 1_500)
    end
  end

  defp handle_bot_in_different_channel(guild_id, current_channel_id) do
    Logger.debug(
      "Skipping handle_bot_in_different_channel due to invalid target: guild_id=#{inspect(guild_id)}, channel_id=#{inspect(current_channel_id)}"
    )

    :noop
  end

  defp handle_join_sound(user_id, previous_state, new_channel_id) do
    is_join_event =
      case previous_state do
        nil -> true
        {nil, _} -> true
        {prev_channel, _} -> prev_channel != new_channel_id
      end

    Logger.info(
      "Join sound check - User: #{user_id}, Previous: #{inspect(previous_state)}, New channel: #{new_channel_id}, Is join: #{is_join_event}"
    )

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

    Logger.info("Join sound query result for user #{user_id}: #{inspect(user_with_sounds)}")

    case user_with_sounds do
      {_user_id, join_sound} when not is_nil(join_sound) ->
        Logger.info("Scheduling join sound: #{join_sound}")
        # Send delayed sound to AudioPlayer instead of self()
        Process.send_after(SoundboardWeb.AudioPlayer, {:play_delayed_sound, join_sound}, 1000)

      _ ->
        Logger.info("No join sound found for user #{user_id}")
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
