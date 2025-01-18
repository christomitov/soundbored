defmodule SoundboardWeb.DiscordHandler do
  use Nostrum.Consumer
  require Logger

  alias Nostrum.Api
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Voice
  alias Soundboard.{Repo, Sound, Accounts.User}
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

  def handle_event({:VOICE_STATE_UPDATE, %{channel_id: nil} = payload, _ws_state}) do
    # Handle disconnection (leaving voice channel)
    Logger.info("User #{payload.user_id} disconnected from voice")

    # Store the last session_id when disconnecting
    State.update_state(payload.user_id, nil, payload.session_id)

    user_with_sounds =
      from(u in User,
        where: u.discord_id == ^to_string(payload.user_id),
        left_join: ls in Sound,
        on: ls.user_id == u.id and ls.is_leave_sound == true,
        select: {u.id, ls.filename},
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
    Logger.info("Voice state check - Payload: #{inspect(payload)}")

    # Get previous state with error handling
    previous_state = State.get_state(payload.user_id)

    # Only handle actual join events by checking both channel and session changes
    is_join_event =
      case previous_state do
        # First join ever
        nil ->
          true

        {prev_channel_id, _prev_session_id} ->
          cond do
            # Different channel from nil = true join
            prev_channel_id == nil and payload.channel_id != nil -> true
            # Different channel = true join (moving between channels)
            prev_channel_id != payload.channel_id and payload.channel_id != nil -> true
            # All other cases (including session changes) = not a join
            true -> false
          end
      end

    # Store current state with error handling
    State.update_state(payload.user_id, payload.channel_id, payload.session_id)

    # Add debug logging
    Logger.debug("""
    Voice state check:
    Previous state: #{inspect(previous_state)}
    Current channel: #{inspect(payload.channel_id)}
    Current session: #{inspect(payload.session_id)}
    Is join event: #{inspect(is_join_event)}
    """)

    if is_join_event do
      # Find user and their configured sounds
      user_with_sounds =
        from(u in User,
          where: u.discord_id == ^to_string(payload.user_id),
          left_join: js in Sound,
          on: js.user_id == u.id and js.is_join_sound == true,
          select: {u.id, js.filename},
          limit: 1
        )
        |> Repo.one()

      case user_with_sounds do
        {_user_id, join_sound} when not is_nil(join_sound) ->
          Logger.info("User joined voice - scheduling sound with delay: #{join_sound}")
          Process.send_after(self(), {:play_delayed_sound, join_sound}, 1000)

        _ ->
          :noop
      end
    else
      Logger.info("Ignoring non-join voice state update")
      :noop
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
        Logger.info("Join command received from user #{msg.author.username}")

        case get_user_voice_channel(msg.guild_id, msg.author.id) do
          nil ->
            Logger.warning("No voice channel found for user #{msg.author.username}")
            Api.create_message(msg.channel_id, "You need to be in a voice channel!")

          channel_id ->
            Logger.info("Found voice channel: #{inspect(channel_id)}")
            Logger.info("Storing voice channel: guild=#{msg.guild_id}, channel=#{channel_id}")

            # Store the current voice channel info in the Discord Handler process
            Process.put(:current_voice_channel, {msg.guild_id, channel_id})
            Voice.join_channel(msg.guild_id, channel_id)

            # Also store it in the AudioPlayer process
            GenServer.cast(
              SoundboardWeb.AudioPlayer,
              {:set_voice_channel, msg.guild_id, channel_id}
            )

            # Verify storage
            stored = Process.get(:current_voice_channel)
            Logger.info("Stored voice channel: #{inspect(stored)}")

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
          Process.delete(:current_voice_channel)
          Voice.leave_channel(msg.guild_id)
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
end
