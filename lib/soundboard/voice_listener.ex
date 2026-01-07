defmodule Soundboard.VoiceListener do
  @moduledoc """
  Automatically listens to voice channel audio when bot joins,
  transcribes speech, and triggers Clawdbot on wake words.

  No manual start/stop needed - hooks into Discord voice events.
  """
  use GenServer
  require Logger

  alias Nostrum.Voice
  alias Soundboard.VoiceListener.ClawdbotAPI
  alias Soundboard.VoiceListener.Transcriber

  @wake_words ["clawd", "clawdbot", "soundbored"]
  @buffer_duration_ms 60_000
  @transcribe_interval_ms 3_000

  defstruct [
    :guild_id,
    :channel_id,
    audio_buffer: [],
    text_buffer: [],
    listening: false
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Called by DiscordHandler when bot joins voice"
  def on_voice_join(guild_id, channel_id) do
    GenServer.cast(__MODULE__, {:voice_joined, guild_id, channel_id})
  end

  @doc "Called by DiscordHandler when bot leaves voice"
  def on_voice_leave(guild_id) do
    GenServer.cast(__MODULE__, {:voice_left, guild_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:voice_joined, guild_id, channel_id}, state) do
    Logger.info("VoiceListener: Bot joined voice in guild #{guild_id}, starting listener")

    case Voice.start_listen_async(guild_id) do
      :ok ->
        schedule_transcription()
        {:noreply, %{state |
          guild_id: guild_id,
          channel_id: channel_id,
          listening: true,
          audio_buffer: [],
          text_buffer: []
        }}

      {:error, reason} ->
        Logger.error("VoiceListener: Failed to start listening: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:voice_left, guild_id}, state) do
    if state.guild_id == guild_id do
      Logger.info("VoiceListener: Bot left voice, stopping listener")
      # Voice listening stops automatically when leaving channel
      {:noreply, %{state | listening: false, guild_id: nil, channel_id: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:voice_incoming, _guild_id, user_id, audio_data}, state) do
    timestamp = System.monotonic_time(:millisecond)
    chunk = %{user_id: user_id, data: audio_data, timestamp: timestamp}

    new_buffer = [chunk | state.audio_buffer]
    |> Enum.filter(& timestamp - &1.timestamp < @buffer_duration_ms)

    {:noreply, %{state | audio_buffer: new_buffer}}
  end

  @impl true
  def handle_info(:transcribe, state) do
    if state.listening and length(state.audio_buffer) > 0 do
      Task.start(fn -> process_audio(state.audio_buffer, state.guild_id) end)
    end

    if state.listening, do: schedule_transcription()
    {:noreply, state}
  end

  @impl true
  def handle_info({:transcription_result, text}, state) do
    Logger.debug("VoiceListener: Transcribed: #{text}")

    timestamp = System.monotonic_time(:millisecond)
    entry = %{text: text, timestamp: timestamp}

    new_text_buffer = [entry | state.text_buffer]
    |> Enum.filter(& timestamp - &1.timestamp < @buffer_duration_ms)
    |> Enum.take(50)

    if contains_wake_word?(text) do
      Logger.info("VoiceListener: Wake word detected!")
      context = Enum.map_join(Enum.reverse(new_text_buffer), " ", & &1.text)
      Task.start(fn -> ClawdbotAPI.process_query(text, context, state.guild_id) end)
    end

    {:noreply, %{state | text_buffer: new_text_buffer}}
  end

  defp schedule_transcription do
    Process.send_after(self(), :transcribe, @transcribe_interval_ms)
  end

  defp process_audio(buffer, _guild_id) do
    audio = buffer |> Enum.sort_by(& &1.timestamp) |> Enum.map_join(& &1.data)

    case Transcriber.transcribe(audio) do
      {:ok, text, _} -> send(__MODULE__, {:transcription_result, text})
      {:error, reason} -> Logger.warning("Transcription failed: #{inspect(reason)}")
    end
  end

  defp contains_wake_word?(text) do
    text_lower = String.downcase(text)
    Enum.any?(@wake_words, &String.contains?(text_lower, &1))
  end
end
