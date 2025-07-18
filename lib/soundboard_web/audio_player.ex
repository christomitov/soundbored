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

  # Server Callbacks
  @impl true
  def init(state) do
    Logger.info("Initializing AudioPlayer with state: #{inspect(state)}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:set_voice_channel, guild_id, channel_id}, state) do
    {:noreply, %{state | voice_channel: {guild_id, channel_id}}}
  end

  @impl true
  def handle_cast(:stop_sound, %{voice_channel: {guild_id, _channel_id}} = state) do
    Logger.info("Stopping all sounds in guild: #{guild_id}")
    Voice.stop(guild_id)
    broadcast_success("All sounds stopped", "System")
    {:noreply, state}
  end

  @impl true
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
  def handle_info({:play_delayed_sound, sound}, state) do
    Logger.info("Playing delayed join sound: #{sound}")
    # Play the sound as System user
    handle_cast({:play_sound, sound, "System"}, state)
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

    case Voice.play(guild_id, play_input, play_type) do
      :ok ->
        track_play_if_needed(sound_name, username)
        broadcast_success(sound_name, username)

      {:error, reason} ->
        Logger.error("Voice.play failed: #{inspect(reason)}")
        broadcast_error("Failed to play sound: #{reason}")
    end
  rescue
    e ->
      Logger.error("Error playing sound: #{inspect(e)}")
      Logger.error("Stack trace: #{inspect(__STACKTRACE__)}")
      broadcast_error("Failed to play sound")
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
        # For local files, Nostrum expects a file:// URL or just the path
        # Since ffmpeg can handle direct paths, we'll use :url type
        Logger.info("Using local file path with :url type")
        {path_or_url, :url}

      _ ->
        Logger.warning("Unknown source type, defaulting to :url type with direct path")
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
    case Voice.join_channel(guild_id, channel_id) do
      :ok ->
        # Give the connection a moment to establish
        Process.sleep(200)

        if Voice.ready?(guild_id) do
          Logger.info("Successfully connected to voice channel")
          true
        else
          Logger.error("Voice connection not ready after join attempt")
          false
        end

      {:error, reason} ->
        Logger.error("Failed to join voice channel: #{inspect(reason)}")
        false
    end
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
        priv_dir = :code.priv_dir(:soundboard)
        path = Path.join([priv_dir, "static/uploads", filename])
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
