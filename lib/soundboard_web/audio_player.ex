defmodule SoundboardWeb.AudioPlayer do
  use GenServer
  require Logger
  alias Nostrum.Voice

  defmodule State do
    defstruct [:voice_channel, :current_playback]
  end

  def start_link(_opts) do
    Logger.info("Starting AudioPlayer GenServer")
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Initializing AudioPlayer with state: #{inspect(state)}")
    {:ok, state}
  end

  def play_sound(sound_name, username) do
    Logger.info("Received play_sound request for: #{sound_name} from #{username}")
    GenServer.cast(__MODULE__, {:play_sound, sound_name, username})
  end

  def set_voice_channel(guild_id, channel_id) do
    Logger.info("Setting voice channel - Guild: #{guild_id}, Channel: #{channel_id}")
    GenServer.cast(__MODULE__, {:set_voice_channel, guild_id, channel_id})
  end

  def handle_cast({:set_voice_channel, guild_id, channel_id}, state) do
    {:noreply, %{state | voice_channel: {guild_id, channel_id}}}
  end

  def handle_cast({:play_sound, _sound_name, _username}, %{voice_channel: nil} = state) do
    broadcast_error("Bot is not connected to a voice channel. Use !join in Discord first.")
    {:noreply, state}
  end

  def handle_cast(
        {:play_sound, sound_name, username},
        %{voice_channel: {guild_id, channel_id}} = state
      ) do
    priv_dir = :code.priv_dir(:soundboard)
    sound_path = Path.join([priv_dir, "static/uploads", sound_name])

    if File.exists?(sound_path) do
      task =
        Task.async(fn ->
          try do
            Voice.stop(guild_id)
            ensure_voice_connected(guild_id, channel_id)

            Voice.play(guild_id, sound_path, :url,
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
            )

            broadcast_success(sound_name, username)
          rescue
            e ->
              Logger.error("Error playing sound: #{inspect(e)}")
              broadcast_error("Failed to play sound")
          end
        end)

      {:noreply, %{state | current_playback: task}}
    else
      broadcast_error("Sound file not found")
      {:noreply, state}
    end
  end

  def handle_info({ref, _result}, %{current_playback: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | current_playback: nil}}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_playback: %Task{ref: ref}} = state
      ) do
    Logger.error("Playback task crashed: #{inspect(reason)}")
    {:noreply, %{state | current_playback: nil}}
  end

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
end
