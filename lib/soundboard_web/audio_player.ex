defmodule SoundboardWeb.AudioPlayer do
  @moduledoc """
  Handles the audio playback.
  """
  use GenServer
  require Logger
  alias Nostrum.Voice
  alias Soundboard.Accounts.User
  alias Soundboard.Sound

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
            try do
              Voice.stop(guild_id)
              ensure_voice_connected(guild_id, channel_id)

              Voice.play(guild_id, path_or_url, :url, get_ffmpeg_options())

              # Track play only after successful playback
              case Soundboard.Repo.get_by(User, username: username) do
                %{id: user_id} -> Soundboard.Stats.track_play(sound_name, user_id)
                nil -> Logger.warning("Could not find user_id for #{username}")
              end

              broadcast_success(sound_name, username)
            rescue
              e ->
                Logger.error("Error playing sound: #{inspect(e)}")
                broadcast_error("Failed to play sound")
            end
          end)

        {:noreply, %{state | current_playback: task}}

      {:error, reason} ->
        broadcast_error(reason)
        {:noreply, state}
    end
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

  defp ensure_voice_connected(guild_id, channel_id) do
    unless Voice.ready?(guild_id) do
      Voice.join_channel(guild_id, channel_id)
      # Process.sleep(100)  # Brief pause to allow connection
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
    case Soundboard.Repo.get_by(Sound, filename: sound_name) do
      %{source_type: "url", url: url} when not is_nil(url) ->
        {:ok, url}

      %{source_type: "local", filename: filename} when not is_nil(filename) ->
        priv_dir = :code.priv_dir(:soundboard)
        path = Path.join([priv_dir, "static/uploads", filename])
        if File.exists?(path), do: {:ok, path}, else: {:error, "Sound file not found"}

      _ ->
        {:error, "Invalid sound configuration"}
    end
  end

  defp get_ffmpeg_options do
    [
      volume: 0.7,
      ffmpeg_args: [
        # Standard sample rate for Opus
        "-ar",
        "48000",
        # Stereo channels
        "-ac",
        "2",
        # Use the Opus codec
        "-c:a",
        "libopus",
        # Lower bitrate for efficiency
        "-b:a",
        "96k",
        # Enable variable bitrate
        "-vbr",
        "on",
        # Optimize for general audio use
        "-application",
        "audio",
        # Standard 20ms frame duration
        "-frame_duration",
        "20",
        # Reduced packet loss simulation
        "-packet_loss",
        "3",
        # Enable forward error correction
        "-fec",
        "1",
        # Lower buffer size for reduced latency
        "-buffer_size",
        "960k",
        # Lower max bitrate for bandwidth control
        "-maxrate",
        "128k",
        # Fewer threads for efficiency
        "-threads",
        "4",
        # Optimize seeking
        "-fflags",
        "+fastseek",
        # Reduced probe size for faster startup
        "-probesize",
        "128k",
        # Lower analysis duration for quick initialization
        "-analyzeduration",
        "2000000",
        "-af",
        "loudnorm=I=-14:LRA=1:TP=-1:dual_mono=true,compand=attacks=0:points=-70/-70|-40/-40|-20/-12|0/-6|20/-6:gain=8"
      ]
    ]
  end
end
