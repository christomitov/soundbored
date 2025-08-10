defmodule SoundboardWeb.AudioPlayer do
  @moduledoc """
  Handles the audio playback.
  """
  use GenServer
  require Logger
  alias Nostrum.Voice
  alias Soundboard.Accounts.User
  alias Soundboard.Sound

  # System users that don't need play tracking
  @system_users ["System", "API User"]

  defmodule State do
    @moduledoc """
    The state of the audio player.
    """
    defstruct [:voice_channel, :current_playback]
  end

  # Client API
  def start_link(_opts) do
    Logger.info("Starting AudioPlayer GenServer")
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  def play_sound(sound_name, username) do
    Logger.info("Received play_sound request for: #{sound_name} from #{username}")
    GenServer.cast(__MODULE__, {:play_sound, sound_name, username})
  end

  def stop_sound do
    Logger.info("Stopping all sounds")
    GenServer.cast(__MODULE__, :stop_sound)
  end

  def set_voice_channel(guild_id, channel_id) do
    Logger.info("Setting voice channel - Guild: #{guild_id}, Channel: #{channel_id}")
    GenServer.cast(__MODULE__, {:set_voice_channel, guild_id, channel_id})
  end

  def current_voice_channel do
    GenServer.call(__MODULE__, :get_voice_channel)
  rescue
    _ -> nil
  end

  # Server Callbacks
  @impl true
  def init(state) do
    Logger.info("Initializing AudioPlayer with state: #{inspect(state)}")
    # Schedule periodic voice connection check
    schedule_voice_check()
    {:ok, state}
  end

  @impl true
  def handle_cast({:set_voice_channel, guild_id, channel_id}, state) do
    # Handle nil values properly - set to nil instead of {nil, nil}
    voice_channel =
      if is_nil(guild_id) or is_nil(channel_id) do
        nil
      else
        {guild_id, channel_id}
      end

    {:noreply, %{state | voice_channel: voice_channel}}
  end

  def handle_cast(:stop_sound, %{voice_channel: {guild_id, _channel_id}} = state) do
    Logger.info("Stopping all sounds in guild: #{guild_id}")
    Voice.stop(guild_id)
    broadcast_success("All sounds stopped", "System")
    {:noreply, state}
  end

  def handle_cast(:stop_sound, state) do
    Logger.info("Attempted to stop sounds but no voice channel connected")
    broadcast_error("Bot is not connected to a voice channel")
    {:noreply, state}
  end

  def handle_cast({:play_sound, _sound_name, _username}, %{voice_channel: nil} = state) do
    broadcast_error("Bot is not connected to a voice channel. Use !join in Discord first.")
    {:noreply, state}
  end

  def handle_cast(
        {:play_sound, sound_name, username},
        %{voice_channel: {guild_id, channel_id}} = state
      ) do
    case get_sound_path(sound_name) do
      {:ok, path_or_url} ->
        task =
          Task.async(fn ->
            play_sound_task(guild_id, channel_id, sound_name, path_or_url, username)
          end)

        {:noreply, %{state | current_playback: task}}

      {:error, reason} ->
        broadcast_error(reason)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_voice_channel, _from, state) do
    {:reply, state.voice_channel, state}
  end

  @impl true
  def handle_info({:play_delayed_sound, sound}, state) do
    Logger.info("Playing delayed join sound: #{sound}")
    # Play the sound as System user
    handle_cast({:play_sound, sound, "System"}, state)
  end

  @impl true
  def handle_info(:check_voice_connection, state) do
    # Check and maintain voice connection health
    new_state =
      case state.voice_channel do
        {guild_id, channel_id} when not is_nil(guild_id) and not is_nil(channel_id) ->
          if Voice.ready?(guild_id) do
            Logger.debug("Voice connection healthy for guild #{guild_id}")
            state
          else
            Logger.warning(
              "Voice connection not ready for guild #{guild_id}, attempting to rejoin"
            )

            # Wrap in try-catch to handle potential errors
            try do
              Voice.join_channel(guild_id, channel_id)
              state
            rescue
              error ->
                Logger.error("Failed to rejoin voice channel: #{inspect(error)}")
                # Clear the voice channel if we can't rejoin
                %{state | voice_channel: nil}
            end
          end

        _ ->
          Logger.debug("No voice channel set")
          state
      end

    # Schedule next check
    schedule_voice_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, _result}, %{current_playback: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | current_playback: nil}}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_playback: %Task{ref: ref}} = state
      ) do
    Logger.error("Playback task crashed: #{inspect(reason)}")
    {:noreply, %{state | current_playback: nil}}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  # Helper function to check if a username is a system user
  defp system_user?(username), do: username in @system_users

  defp play_sound_task(guild_id, channel_id, sound_name, path_or_url, username) do
    # Stop any currently playing sound
    Voice.stop(guild_id)

    # Ensure we're connected and ready
    if ensure_voice_ready(guild_id, channel_id) do
      play_sound_with_connection(guild_id, sound_name, path_or_url, username)
    else
      Logger.error("Failed to establish voice connection")
      broadcast_error("Failed to connect to voice channel")
    end
  end

  defp play_sound_with_connection(guild_id, sound_name, path_or_url, username) do
    {play_input, play_type} = prepare_play_input(sound_name, path_or_url)

    Logger.info(
      "Calling Voice.play with guild_id: #{guild_id}, input: #{play_input}, type: #{play_type}"
    )

    # Check voice state
    Logger.info("Voice ready: #{Voice.ready?(guild_id)}, Playing: #{Voice.playing?(guild_id)}")

    # Don't use realtime flag for local files, it can cause issues
    # Only use realtime for streaming/URL sources
    play_options = [volume: 1.0]
    Logger.info("Play options: #{inspect(play_options)}")

    # Keep track of attempts
    play_with_retries(guild_id, play_input, play_type, play_options, sound_name, username, 0)
  end

  defp play_with_retries(
         guild_id,
         play_input,
         play_type,
         play_options,
         sound_name,
         username,
         attempt
       )
       when attempt < 3 do
    case Voice.play(guild_id, play_input, play_type, play_options) do
      :ok ->
        Logger.info("Voice.play succeeded for #{sound_name} (attempt #{attempt + 1})")
        # Add a small delay to ensure audio starts properly
        Process.sleep(100)
        track_play_if_needed(sound_name, username)
        broadcast_success(sound_name, username)
        :ok

      {:error, "Audio already playing in voice channel."} ->
        Logger.warning("Audio still playing on attempt #{attempt + 1}, waiting...")
        # Wait for current audio to finish
        wait_for_audio_to_finish(guild_id, 3000)

        play_with_retries(
          guild_id,
          play_input,
          play_type,
          play_options,
          sound_name,
          username,
          attempt + 1
        )

      {:error, "Must be connected to voice channel to play audio."} ->
        Logger.error("Voice connection lost, attempting to reconnect...")

        handle_voice_reconnect(
          guild_id,
          play_input,
          play_type,
          play_options,
          sound_name,
          username,
          attempt
        )

      {:error, reason} ->
        Logger.error("Voice.play failed: #{inspect(reason)} (attempt #{attempt + 1})")
        broadcast_error("Failed to play sound: #{reason}")
        :error
    end
  end

  defp play_with_retries(
         _guild_id,
         _play_input,
         _play_type,
         _play_options,
         sound_name,
         _username,
         attempt
       ) do
    Logger.error("Exceeded max retries (#{attempt}) for playing #{sound_name}")
    broadcast_error("Failed to play sound after multiple attempts")
    :error
  end

  defp handle_voice_reconnect(
         guild_id,
         play_input,
         play_type,
         play_options,
         sound_name,
         username,
         attempt
       ) do
    # Get the channel from state
    case GenServer.call(__MODULE__, :get_voice_channel) do
      {^guild_id, channel_id} ->
        Logger.info("Rejoining voice channel #{channel_id}")

        # Voice.join_channel returns :ok or crashes (no_return)
        try do
          Voice.join_channel(guild_id, channel_id)
          # Give it more time to fully connect
          Process.sleep(2000)

          play_with_retries(
            guild_id,
            play_input,
            play_type,
            play_options,
            sound_name,
            username,
            attempt + 1
          )
        rescue
          error ->
            Logger.error("Failed to rejoin voice channel: #{inspect(error)}")
            broadcast_error("Failed to reconnect to voice channel")
            :error
        end

      _ ->
        Logger.error("No voice channel info available")
        broadcast_error("Voice channel not configured")
        :error
    end
  end

  defp wait_for_audio_to_finish(guild_id, max_wait) do
    start_time = System.monotonic_time(:millisecond)

    Stream.repeatedly(fn ->
      if Voice.playing?(guild_id) do
        Process.sleep(100)
        :waiting
      else
        :done
      end
    end)
    |> Stream.take_while(fn status ->
      elapsed = System.monotonic_time(:millisecond) - start_time
      status == :waiting and elapsed < max_wait
    end)
    |> Stream.run()
  end

  defp schedule_voice_check do
    # Check voice connection every 30 seconds
    Process.send_after(self(), :check_voice_connection, 30_000)
  end

  defp prepare_play_input(sound_name, path_or_url) do
    sound = Soundboard.Repo.get_by(Sound, filename: sound_name)
    Logger.info("Playing sound: #{inspect(sound)}")
    Logger.info("Original path/URL: #{path_or_url}")

    case sound do
      %{source_type: "url"} ->
        Logger.info("Using URL directly for remote sound")
        {path_or_url, :url}

      %{source_type: "local"} ->
        # For local files, use raw path with :url type
        # ffmpeg can read local files directly
        Logger.info("Using raw path for local file with :url type")
        {path_or_url, :url}

      _ ->
        # Default to raw path for unknown types (likely local files)
        Logger.warning("Unknown source type, defaulting to raw path with :url type")
        {path_or_url, :url}
    end
  end

  defp track_play_if_needed(sound_name, username) do
    if system_user?(username) do
      Logger.info("Skipping play tracking for system user: #{username}")
    else
      case Soundboard.Repo.get_by(User, username: username) do
        %{id: user_id} -> Soundboard.Stats.track_play(sound_name, user_id)
        nil -> Logger.warning("Could not find user_id for #{username}")
      end
    end
  end

  defp ensure_voice_ready(guild_id, channel_id) do
    if Voice.ready?(guild_id) do
      Logger.info("Voice connection ready for guild #{guild_id}")
      true
    else
      Logger.info("Voice not ready, attempting to join channel #{channel_id}")
      join_and_verify_channel(guild_id, channel_id)
    end
  end

  defp join_and_verify_channel(guild_id, channel_id) do
    # Voice.join_channel returns :ok or crashes (no_return)
    # Using rescue to handle potential crashes
    Voice.join_channel(guild_id, channel_id)

    # Give the connection a moment to establish
    Process.sleep(200)

    if Voice.ready?(guild_id) do
      Logger.info("Successfully connected to voice channel")
      true
    else
      Logger.error("Voice connection not ready after join attempt")
      false
    end
  rescue
    error ->
      Logger.error("Failed to join voice channel: #{inspect(error)}")
      false
  end

  defp broadcast_success(sound_name, username) do
    Phoenix.PubSub.broadcast(
      Soundboard.PubSub,
      "soundboard",
      {:sound_played, %{filename: sound_name, played_by: username}}
    )
  end

  defp broadcast_error(message) do
    Phoenix.PubSub.broadcast(
      Soundboard.PubSub,
      "soundboard",
      {:error, message}
    )
  end

  defp get_sound_path(sound_name) do
    Logger.info("Getting sound path for: #{sound_name}")

    case Soundboard.Repo.get_by(Sound, filename: sound_name) do
      nil ->
        Logger.error("Sound not found in database: #{sound_name}")
        {:error, "Sound not found"}

      %{source_type: "url", url: url} when not is_nil(url) ->
        Logger.info("Found URL sound: #{url}")
        {:ok, url}

      %{source_type: "local", filename: filename} when not is_nil(filename) ->
        # Check if we're in Docker production environment
        path =
          if File.exists?("/app/priv/static/uploads") do
            "/app/priv/static/uploads/#{filename}"
          else
            priv_dir = :code.priv_dir(:soundboard)
            Path.join([priv_dir, "static/uploads", filename])
          end

        Logger.info("Checking local file path: #{path}")

        if File.exists?(path) do
          Logger.info("Local file exists: #{path}")
          {:ok, path}
        else
          Logger.error("Local file not found: #{path}")
          {:error, "Sound file not found at #{path}"}
        end

      sound ->
        Logger.error("Invalid sound configuration: #{inspect(sound)}")
        {:error, "Invalid sound configuration"}
    end
  end
end
