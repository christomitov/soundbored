defmodule Soundboard.AudioPlayer.PlaybackQueue do
  @moduledoc false

  require Logger

  alias Soundboard.AudioPlayer.{PlaybackEngine, SoundLibrary, State}
  alias Soundboard.Discord.Voice

  @type play_request :: %{
          guild_id: String.t(),
          channel_id: String.t(),
          sound_name: String.t(),
          path_or_url: String.t(),
          volume: number(),
          actor: term()
        }

  @spec build_request({String.t(), String.t()}, String.t(), term()) ::
          {:ok, play_request()} | {:error, String.t()}
  def build_request({guild_id, channel_id}, sound_name, actor) do
    case SoundLibrary.get_sound_path(sound_name) do
      {:ok, {path_or_url, volume}} ->
        {:ok,
         %{
           guild_id: guild_id,
           channel_id: channel_id,
           sound_name: sound_name,
           path_or_url: path_or_url,
           volume: volume,
           actor: actor
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec enqueue(State.t(), play_request(), pos_integer()) :: State.t()
  def enqueue(%State{} = state, request, interrupt_watchdog_ms) do
    case state.current_playback do
      nil ->
        state
        |> cancel_interrupt_watchdog()
        |> Map.merge(%{interrupting: false, interrupt_watchdog_attempt: 0})
        |> start_playback(request)

      _ ->
        state
        |> Map.put(:pending_request, request)
        |> maybe_interrupt_current(interrupt_watchdog_ms)
    end
  end

  @spec clear_all(State.t()) :: State.t()
  def clear_all(%State{} = state) do
    state
    |> clear_current_playback()
    |> Map.merge(%{
      pending_request: nil,
      interrupting: false,
      interrupt_watchdog_attempt: 0
    })
  end

  @spec handle_task_result(State.t(), term()) :: State.t()
  def handle_task_result(
        %State{current_playback: %{sound_name: sound_name} = current} = state,
        result
      ) do
    case result do
      :ok ->
        %{
          state
          | current_playback:
              current
              |> Map.put(:task_ref, nil)
              |> Map.put(:task_pid, nil)
        }

      :error ->
        Logger.error("Playback start failed for #{sound_name}")
        state |> clear_current_playback() |> maybe_start_pending()
    end
  end

  @spec handle_task_down(State.t(), term()) :: State.t()
  def handle_task_down(%State{} = state, reason) do
    Logger.error("Playback task crashed: #{inspect(reason)}")
    state |> clear_current_playback() |> maybe_start_pending()
  end

  @spec handle_interrupt_watchdog(
          State.t(),
          String.t(),
          non_neg_integer(),
          pos_integer(),
          pos_integer()
        ) ::
          State.t()
  def handle_interrupt_watchdog(
        %State{interrupting: true, interrupt_watchdog_attempt: attempt} = state,
        guild_id,
        attempt,
        max_attempts,
        interrupt_watchdog_ms
      ) do
    cond do
      state.current_playback == nil ->
        state |> reset_interrupt_state() |> maybe_start_pending()

      attempt >= max_attempts ->
        Logger.warning(
          "Interrupt watchdog timed out for guild #{guild_id}; forcing latest request"
        )

        Voice.stop(guild_id)
        state |> clear_current_playback() |> maybe_start_pending()

      match?({:ok, true}, safe_voice_playing(guild_id)) ->
        Logger.debug(
          "Interrupt watchdog: audio still playing in guild #{guild_id}, retrying stop"
        )

        Voice.stop(guild_id)
        schedule_interrupt_watchdog(state, guild_id, attempt + 1, interrupt_watchdog_ms)

      true ->
        Logger.debug("Interrupt watchdog: playback already stopped for guild #{guild_id}")
        state |> clear_current_playback() |> maybe_start_pending()
    end
  end

  def handle_interrupt_watchdog(%State{} = state, _guild_id, _attempt, _max_attempts, _delay_ms),
    do: state

  @spec handle_playback_finished(State.t(), String.t()) :: State.t()
  def handle_playback_finished(%State{} = state, guild_id) do
    cond do
      match?(%{guild_id: ^guild_id}, state.current_playback) ->
        state
        |> clear_current_playback()
        |> maybe_start_pending()

      state.interrupting and match?({^guild_id, _}, state.voice_channel) ->
        state
        |> reset_interrupt_state()
        |> maybe_start_pending()

      true ->
        state
    end
  end

  defp start_playback(state, request) do
    task =
      Task.async(fn ->
        PlaybackEngine.play(
          request.guild_id,
          request.channel_id,
          request.sound_name,
          request.path_or_url,
          request.volume,
          request.actor
        )
      end)

    %{
      state
      | current_playback: request |> Map.put(:task_ref, task.ref) |> Map.put(:task_pid, task.pid)
    }
  end

  defp maybe_interrupt_current(%State{current_playback: %{guild_id: guild_id}} = state, delay_ms) do
    Logger.debug("Interrupting current playback in guild #{guild_id} for latest request")
    Voice.stop(guild_id)

    if match?({:ok, true}, safe_voice_playing(guild_id)) do
      state
      |> Map.put(:interrupting, true)
      |> schedule_interrupt_watchdog(guild_id, 1, delay_ms)
    else
      Logger.debug("Interrupt fast-path: playback stopped immediately in guild #{guild_id}")

      state
      |> clear_current_playback()
      |> maybe_start_pending()
    end
  end

  defp maybe_interrupt_current(%State{} = state, _delay_ms), do: state

  defp maybe_start_pending(%State{pending_request: nil} = state), do: state

  defp maybe_start_pending(%State{} = state) do
    request = state.pending_request

    case state.voice_channel do
      {guild_id, channel_id}
      when guild_id == request.guild_id and channel_id == request.channel_id ->
        state
        |> Map.put(:pending_request, nil)
        |> start_playback(request)

      _ ->
        %{state | pending_request: nil}
    end
  end

  defp clear_current_playback(%State{} = state) do
    cancel_playback_task(state.current_playback)

    state
    |> cancel_interrupt_watchdog()
    |> Map.merge(%{
      current_playback: nil,
      interrupting: false,
      interrupt_watchdog_attempt: 0
    })
  end

  defp reset_interrupt_state(%State{} = state) do
    state
    |> cancel_interrupt_watchdog()
    |> Map.merge(%{interrupting: false, interrupt_watchdog_attempt: 0})
  end

  defp schedule_interrupt_watchdog(%State{} = state, guild_id, attempt, delay_ms) do
    state = cancel_interrupt_watchdog(state)

    ref = Process.send_after(self(), {:interrupt_watchdog, guild_id, attempt}, delay_ms)

    %{state | interrupt_watchdog_ref: ref, interrupt_watchdog_attempt: attempt}
  end

  defp cancel_interrupt_watchdog(%State{interrupt_watchdog_ref: nil} = state), do: state

  defp cancel_interrupt_watchdog(%State{} = state) do
    Process.cancel_timer(state.interrupt_watchdog_ref)
    %{state | interrupt_watchdog_ref: nil}
  end

  defp cancel_playback_task(nil), do: :ok

  defp cancel_playback_task(%{task_pid: pid, task_ref: ref}) when is_pid(pid) do
    if is_reference(ref), do: Process.demonitor(ref, [:flush])

    if Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    :ok
  end

  defp cancel_playback_task(_), do: :ok

  defp safe_voice_playing(guild_id) do
    {:ok, Voice.playing?(guild_id)}
  rescue
    error -> {:error, {:voice_playing_unavailable, Exception.message(error)}}
  end
end
