defmodule Soundboard.VoiceListener do
  @moduledoc """
  Listens to voice channel audio, transcribes it, and triggers Clawdbot
  when wake words are detected.
  
  Uses Nostrum's voice listening capabilities to capture incoming audio,
  runs it through Whisper for speech-to-text, and maintains a rolling
  buffer of recent conversation.
  """
  use GenServer
  require Logger
  
  alias Nostrum.Voice
  alias Soundboard.VoiceListener.{Transcriber, ClawdbotAPI}
  
  @wake_words ["clawd", "clawdbot", "soundbored"]
  @buffer_duration_ms 60_000  # Keep 60 seconds of context
  @transcribe_interval_ms 3_000  # Transcribe every 3 seconds
  
  defstruct [
    :guild_id,
    :channel_id,
    :listening,
    :audio_buffer,
    :text_buffer,
    :last_transcribe
  ]

  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def start_listening(guild_id, channel_id) do
    GenServer.call(__MODULE__, {:start_listening, guild_id, channel_id})
  end
  
  def stop_listening do
    GenServer.call(__MODULE__, :stop_listening)
  end
  
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server Callbacks
  
  @impl true
  def init(_opts) do
    state = %__MODULE__{
      listening: false,
      audio_buffer: [],
      text_buffer: [],
      last_transcribe: System.monotonic_time(:millisecond)
    }
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_listening, guild_id, channel_id}, _from, state) do
    Logger.info("Starting voice listener for guild #{guild_id}, channel #{channel_id}")
    
    # Start async listening with Nostrum
    case Voice.start_listen_async(guild_id) do
      :ok ->
        new_state = %{state | 
          guild_id: guild_id,
          channel_id: channel_id,
          listening: true,
          audio_buffer: [],
          text_buffer: []
        }
        # Start periodic transcription
        schedule_transcription()
        {:reply, :ok, new_state}
      
      {:error, reason} = error ->
        Logger.error("Failed to start voice listening: #{inspect(reason)}")
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:stop_listening, _from, state) do
    if state.guild_id do
      Voice.stop_listen(state.guild_id)
    end
    
    new_state = %{state | listening: false, guild_id: nil, channel_id: nil}
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      listening: state.listening,
      guild_id: state.guild_id,
      channel_id: state.channel_id,
      buffer_size: length(state.text_buffer)
    }
    {:reply, status, state}
  end
  
  @impl true
  def handle_info({:voice_incoming, guild_id, user_id, audio_data}, state) do
    # Collect audio data into buffer
    timestamp = System.monotonic_time(:millisecond)
    audio_chunk = %{
      user_id: user_id,
      data: audio_data,
      timestamp: timestamp
    }
    
    # Add to buffer and prune old entries
    new_buffer = [audio_chunk | state.audio_buffer]
    |> Enum.filter(fn chunk -> 
      timestamp - chunk.timestamp < @buffer_duration_ms 
    end)
    
    {:noreply, %{state | audio_buffer: new_buffer}}
  end
  
  @impl true
  def handle_info(:transcribe, state) do
    if state.listening and length(state.audio_buffer) > 0 do
      # Process audio buffer through Whisper
      Task.start(fn ->
        process_audio_buffer(state.audio_buffer, state.guild_id)
      end)
    end
    
    if state.listening do
      schedule_transcription()
    end
    
    {:noreply, %{state | last_transcribe: System.monotonic_time(:millisecond)}}
  end
  
  @impl true
  def handle_info({:transcription_result, text, user_id}, state) do
    Logger.debug("Transcription from user #{user_id}: #{text}")
    
    timestamp = System.monotonic_time(:millisecond)
    entry = %{text: text, user_id: user_id, timestamp: timestamp}
    
    # Add to text buffer and prune old entries
    new_text_buffer = [entry | state.text_buffer]
    |> Enum.filter(fn e -> timestamp - e.timestamp < @buffer_duration_ms end)
    |> Enum.take(50)  # Keep max 50 entries
    
    # Check for wake words
    if contains_wake_word?(text) do
      Logger.info("Wake word detected! Processing query...")
      context = build_context(new_text_buffer)
      Task.start(fn -> 
        ClawdbotAPI.process_query(text, context, state.guild_id) 
      end)
    end
    
    {:noreply, %{state | text_buffer: new_text_buffer}}
  end
  
  # Private Functions
  
  defp schedule_transcription do
    Process.send_after(self(), :transcribe, @transcribe_interval_ms)
  end
  
  defp process_audio_buffer(buffer, guild_id) do
    # Combine audio chunks and send to Whisper
    audio_data = buffer
    |> Enum.sort_by(& &1.timestamp)
    |> Enum.map(& &1.data)
    |> Enum.join()
    
    case Transcriber.transcribe(audio_data) do
      {:ok, text, user_id} ->
        send(__MODULE__, {:transcription_result, text, user_id})
      {:error, reason} ->
        Logger.warning("Transcription failed: #{inspect(reason)}")
    end
  end
  
  defp contains_wake_word?(text) do
    text_lower = String.downcase(text)
    Enum.any?(@wake_words, fn word -> 
      String.contains?(text_lower, word) 
    end)
  end
  
  defp build_context(text_buffer) do
    text_buffer
    |> Enum.reverse()
    |> Enum.map(fn entry -> entry.text end)
    |> Enum.join(" ")
  end
end
