defmodule SoundboardWeb.DiscordHandler do
  use Nostrum.Consumer
  require Logger

  alias Nostrum.Api
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Voice
  alias Soundboard.{Repo, Sound, Accounts.User, UserSoundSetting}
  import Ecto.Query

  # State GenServer
  defmodule State do
    use GenServer

    def start_link(_) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def init(_) do
      {:ok, %{voice_states: %{}}}
    end

    def get_state(user_id) do
      try do
        GenServer.call(__MODULE__, {:get_state, user_id})
      catch
        :exit, _ -> nil
      end
    end

    def update_state(user_id, channel_id, session_id) do
      try do
        GenServer.cast(__MODULE__, {:update_state, user_id, channel_id, session_id})
      catch
        :exit, _ -> :error
      end
    end

    def handle_call({:get_state, user_id}, _from, state) do
      {:reply, Map.get(state.voice_states, user_id), state}
    end

    def handle_cast({:update_state, user_id, channel_id, session_id}, state) do
      {:noreply,
       %{state | voice_states: Map.put(state.voice_states, user_id, {channel_id, session_id})}}
    end
  end

  def start_link do
    Logger.info("Starting DiscordHandler...")
    result = Nostrum.Consumer.start_link(__MODULE__)

    # Check all guilds for voice channels with users
    Task.start(fn ->
      Logger.info("Starting voice channel check task...")
      # Give Discord more time to fully initialize
      Process.sleep(5000)

      case GuildCache.all() do
        [] ->
          Logger.warning("No guilds found in cache. Discord may not be ready.")

        guilds ->
          # Convert stream to list
          guilds = Enum.to_list(guilds)
          Logger.info("Found #{length(guilds)} guilds")

          for guild <- guilds do
            Logger.info("Checking guild #{guild.id} for voice channels...")
            check_and_join_voice(guild)
          end
      end
    end)

    result
  end

  # Add helper function for leaving voice channel
  defp leave_voice_channel(guild_id) do
    Logger.info("Bot leaving voice channel in guild #{guild_id}")
    Process.delete(:current_voice_channel)
    Voice.leave_channel(guild_id)

    # Update AudioPlayer
    GenServer.cast(
      SoundboardWeb.AudioPlayer,
      {:set_voice_channel, nil, nil}
    )
  end

  # Add helper function for joining voice channel
  defp join_voice_channel(guild_id, channel_id) do
    Logger.info("Bot joining voice channel #{channel_id} in guild #{guild_id}")
    Process.put(:current_voice_channel, {guild_id, channel_id})
    Voice.join_channel(guild_id, channel_id)

    # Update AudioPlayer
    GenServer.cast(
      SoundboardWeb.AudioPlayer,
      {:set_voice_channel, guild_id, channel_id}
    )
  end

  # Simplified check_users_in_voice function - no bot token needed
  defp check_users_in_voice(guild_id, channel_id) do
    guild = GuildCache.get!(guild_id)

    # Count total users in the specified channel
    users_in_channel =
      guild.voice_states
      |> Enum.count(fn vs ->
        vs.channel_id == channel_id
      end)

    Logger.info("""
    Voice state check:
    Channel ID: #{channel_id}
    Users in channel: #{users_in_channel}
    Voice states: #{inspect(guild.voice_states)}
    """)

    users_in_channel
  end

  def handle_event({:VOICE_STATE_UPDATE, %{channel_id: nil} = payload, _ws_state}) do
    # Handle disconnection (leaving voice channel)
    Logger.info("User #{payload.user_id} disconnected from voice")
    State.update_state(payload.user_id, nil, payload.session_id)

    # Check if we're in a channel
    case get_current_voice_channel() do
      {guild_id, channel_id} ->
        guild = GuildCache.get!(guild_id)

        # Count ALL users in our current channel
        users_in_channel =
          guild.voice_states
          |> Enum.count(fn vs ->
            vs.channel_id == channel_id
          end)

        Logger.info("""
        Disconnect check:
        Channel ID: #{channel_id}
        Users in channel: #{users_in_channel}
        Voice states: #{inspect(guild.voice_states)}
        """)

        # If 1 or fewer users in channel (just the bot), leave
        if users_in_channel <= 1 do
          Logger.info(
            "Only bot remaining in channel (users: #{users_in_channel}), forcing disconnect"
          )

          leave_voice_channel(guild_id)
        end

      _ ->
        :noop
    end

    # Handle leave sound
    user_with_sounds =
      from(u in User,
        where: u.discord_id == ^to_string(payload.user_id),
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

  def handle_event({:VOICE_STATE_UPDATE, payload, _ws_state}) do
    Logger.info("Voice state update received: #{inspect(payload)}")

    # Update state tracking
    previous_state = State.get_state(payload.user_id)
    State.update_state(payload.user_id, payload.channel_id, payload.session_id)

    # Handle channel join/leave logic
    case get_current_voice_channel() do
      nil when payload.channel_id != nil ->
        # Bot not in channel but user joined one - join their channel
        join_voice_channel(payload.guild_id, payload.channel_id)

      {guild_id, channel_id} ->
        # Bot in channel - check if we should leave
        users = check_users_in_voice(guild_id, channel_id)
        # Changed to <= 1
        if users <= 1, do: leave_voice_channel(guild_id)

      _ ->
        :noop
    end

    # Handle join sound if this was a join event
    is_join_event =
      case previous_state do
        nil -> true
        {nil, _} -> true
        {prev_channel, _} -> prev_channel != payload.channel_id
      end

    if is_join_event do
      user_with_sounds =
        from(u in User,
          where: u.discord_id == ^to_string(payload.user_id),
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
            Api.create_message(msg.channel_id, "You need to be in a voice channel!")

          channel_id ->
            join_voice_channel(msg.guild_id, channel_id)

            # Send web interface URL
            scheme = System.get_env("SCHEME")

            web_url =
              Application.get_env(:soundboard, SoundboardWeb.Endpoint)[:url][:host] || "localhost"

            url = "#{scheme}://#{web_url}"

            Api.create_message(msg.channel_id, """
            Joined your voice channel!
            Access the soundboard here: #{url}
            """)
        end

      "!leave" ->
        if msg.guild_id do
          leave_voice_channel(msg.guild_id)
          Api.create_message(msg.channel_id, "Left the voice channel!")
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
end
