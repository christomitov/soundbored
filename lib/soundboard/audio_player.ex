defmodule Soundboard.AudioPlayer do
  @moduledoc """
  Handles audio playback coordination.
  """

  use GenServer

  alias Soundboard.AudioPlayer.{Notifier, PlaybackQueue, SoundLibrary, VoiceSession}
  alias Soundboard.Discord.Voice

  @interrupt_watchdog_ms 35
  @interrupt_watchdog_max_attempts 20

  defmodule State do
    @moduledoc """
    The state of the audio player.
    """

    defstruct [
      :voice_channel,
      :current_playback,
      :pending_request,
      :interrupting,
      :interrupt_watchdog_ref,
      :interrupt_watchdog_attempt
    ]

    @type t :: %__MODULE__{
            voice_channel: {String.t(), String.t()} | nil,
            current_playback: map() | nil,
            pending_request: map() | nil,
            interrupting: boolean() | nil,
            interrupt_watchdog_ref: reference() | nil,
            interrupt_watchdog_attempt: non_neg_integer() | nil
          }
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  def play_sound(sound_name, actor) do
    GenServer.cast(__MODULE__, {:play_sound, sound_name, actor})
  end

  def stop_sound do
    GenServer.cast(__MODULE__, :stop_sound)
  end

  def set_voice_channel(guild_id, channel_id) do
    GenServer.cast(__MODULE__, {:set_voice_channel, guild_id, channel_id})
  end

  def playback_finished(guild_id) do
    GenServer.cast(__MODULE__, {:playback_finished, guild_id})
  end

  def current_voice_channel do
    {:ok, GenServer.call(__MODULE__, :get_voice_channel)}
  rescue
    error -> {:error, {:voice_channel_unavailable, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:voice_channel_unavailable, reason}}
  end

  @doc """
  Removes any cached metadata for the given `sound_name` so future plays use fresh data.
  """
  def invalidate_cache(sound_name), do: SoundLibrary.invalidate_cache(sound_name)

  @impl true
  def init(state) do
    SoundLibrary.ensure_cache()
    schedule_voice_check()

    {:ok,
     %{
       state
       | current_playback: nil,
         pending_request: nil,
         interrupting: false,
         interrupt_watchdog_ref: nil,
         interrupt_watchdog_attempt: 0
     }}
  end

  @impl true
  def handle_cast({:set_voice_channel, guild_id, channel_id}, state) do
    next_state =
      case VoiceSession.normalize_channel(guild_id, channel_id) do
        nil ->
          state
          |> PlaybackQueue.clear_all()
          |> Map.put(:voice_channel, nil)

        voice_channel ->
          %{state | voice_channel: voice_channel}
      end

    {:noreply, next_state}
  end

  def handle_cast(:stop_sound, %{voice_channel: {guild_id, _channel_id}} = state) do
    Voice.stop(guild_id)
    Notifier.sound_played("All sounds stopped", "System")

    {:noreply, PlaybackQueue.clear_all(state)}
  end

  def handle_cast(:stop_sound, state) do
    Notifier.error("Bot is not connected to a voice channel")
    {:noreply, state}
  end

  def handle_cast({:playback_finished, guild_id}, state) do
    {:noreply, PlaybackQueue.handle_playback_finished(state, guild_id)}
  end

  def handle_cast({:play_sound, _sound_name, _actor}, %{voice_channel: nil} = state) do
    Notifier.error("Bot is not connected to a voice channel. Use !join in Discord first.")
    {:noreply, state}
  end

  def handle_cast({:play_sound, sound_name, actor}, %{voice_channel: voice_channel} = state) do
    case PlaybackQueue.build_request(voice_channel, sound_name, actor) do
      {:ok, request} ->
        {:noreply, PlaybackQueue.enqueue(state, request, @interrupt_watchdog_ms)}

      {:error, reason} ->
        Notifier.error(reason)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_voice_channel, _from, state) do
    {:reply, state.voice_channel, state}
  end

  @impl true
  def handle_info(:check_voice_connection, state) do
    schedule_voice_check()
    {:noreply, VoiceSession.maintain_connection(state)}
  end

  @impl true
  def handle_info({ref, result}, %{current_playback: %{task_ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, PlaybackQueue.handle_task_result(state, result)}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_playback: %{task_ref: ref}} = state
      ) do
    {:noreply, PlaybackQueue.handle_task_down(state, reason)}
  end

  @impl true
  def handle_info({:interrupt_watchdog, guild_id, attempt}, state) do
    {:noreply,
     PlaybackQueue.handle_interrupt_watchdog(
       state,
       guild_id,
       attempt,
       @interrupt_watchdog_max_attempts,
       @interrupt_watchdog_ms
     )}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp schedule_voice_check do
    Process.send_after(self(), :check_voice_connection, 30_000)
  end
end
