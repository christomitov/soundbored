defmodule Soundboard.AudioPlayer do
  @moduledoc """
  Handles the audio playback.
  """
  use GenServer
  require Logger

  alias Soundboard.Discord.Voice
  alias Soundboard.AudioPlayer.{PlaybackEngine, SoundLibrary}

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
  end

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

  def playback_finished(guild_id) do
    GenServer.cast(__MODULE__, {:playback_finished, guild_id})
  end

  def current_voice_channel do
    GenServer.call(__MODULE__, :get_voice_channel)
  rescue
    _ -> nil
  end

  @doc """
  Removes any cached metadata for the given `sound_name` so future plays use fresh data.
  """
  def invalidate_cache(sound_name), do: SoundLibrary.invalidate_cache(sound_name)

  @impl true
  def init(state) do
    Logger.info("Initializing AudioPlayer with state: #{inspect(state)}")
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
    voice_channel =
      if is_nil(guild_id) or is_nil(channel_id) do
        nil
      else
        {guild_id, channel_id}
      end

    next_state =
      case voice_channel do
        nil ->
          state
          |> clear_current_playback()
          |> Map.merge(%{
            voice_channel: nil,
            pending_request: nil,
            interrupting: false,
            interrupt_watchdog_attempt: 0
          })

        _ ->
          %{state | voice_channel: voice_channel}
      end

    {:noreply, next_state}
  end

  def handle_cast(:stop_sound, %{voice_channel: {guild_id, _channel_id}} = state) do
    Logger.info("Stopping all sounds in guild: #{guild_id}")
    Voice.stop(guild_id)
    broadcast_success("All sounds stopped", "System")

    {:noreply,
     state
     |> clear_current_playback()
     |> Map.merge(%{
       pending_request: nil,
       interrupting: false,
       interrupt_watchdog_attempt: 0
     })}
  end

  def handle_cast(:stop_sound, state) do
    Logger.info("Attempted to stop sounds but no voice channel connected")
    broadcast_error("Bot is not connected to a voice channel")
    {:noreply, state}
  end

  def handle_cast({:playback_finished, guild_id}, state) do
    {:noreply, handle_playback_finished(state, guild_id)}
  end

  def handle_cast({:play_sound, _sound_name, _username}, %{voice_channel: nil} = state) do
    broadcast_error("Bot is not connected to a voice channel. Use !join in Discord first.")
    {:noreply, state}
  end

  def handle_cast(
        {:play_sound, sound_name, username},
        %{voice_channel: {guild_id, channel_id}} = state
      ) do
    case SoundLibrary.get_sound_path(sound_name) do
      {:ok, {path_or_url, volume}} ->
        request = %{
          guild_id: guild_id,
          channel_id: channel_id,
          sound_name: sound_name,
          path_or_url: path_or_url,
          volume: volume,
          username: username
        }

        new_state =
          case state.current_playback do
            nil ->
              state
              |> cancel_interrupt_watchdog()
              |> Map.merge(%{interrupting: false, interrupt_watchdog_attempt: 0})
              |> start_playback(request)

            _ ->
              state
              |> Map.put(:pending_request, request)
              |> maybe_interrupt_current()
          end

        {:noreply, new_state}

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
  def handle_info(:check_voice_connection, state) do
    new_state = maintain_voice_connection(state)
    schedule_voice_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({ref, result}, %{current_playback: %{task_ref: ref} = current} = state) do
    Process.demonitor(ref, [:flush])

    next_state =
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
          Logger.error("Playback start failed for #{current.sound_name}")
          state |> clear_current_playback() |> maybe_start_pending()
      end

    {:noreply, next_state}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_playback: %{task_ref: ref}} = state
      ) do
    Logger.error("Playback task crashed: #{inspect(reason)}")
    {:noreply, state |> clear_current_playback() |> maybe_start_pending()}
  end

  @impl true
  def handle_info(
        {:interrupt_watchdog, guild_id, attempt},
        %{interrupting: true, interrupt_watchdog_attempt: attempt} = state
      ) do
    cond do
      state.current_playback == nil ->
        {:noreply, state |> reset_interrupt_state() |> maybe_start_pending()}

      attempt >= @interrupt_watchdog_max_attempts ->
        Logger.warning(
          "Interrupt watchdog timed out for guild #{guild_id}; forcing latest request"
        )

        Voice.stop(guild_id)
        {:noreply, state |> clear_current_playback() |> maybe_start_pending()}

      Voice.playing?(guild_id) ->
        Logger.debug(
          "Interrupt watchdog: audio still playing in guild #{guild_id}, retrying stop"
        )

        Voice.stop(guild_id)
        {:noreply, schedule_interrupt_watchdog(state, guild_id, attempt + 1)}

      true ->
        Logger.debug("Interrupt watchdog: playback already stopped for guild #{guild_id}")
        {:noreply, state |> clear_current_playback() |> maybe_start_pending()}
    end
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp start_playback(state, request) do
    task =
      Task.async(fn ->
        PlaybackEngine.play(
          request.guild_id,
          request.channel_id,
          request.sound_name,
          request.path_or_url,
          request.volume,
          request.username
        )
      end)

    %{
      state
      | current_playback: request |> Map.put(:task_ref, task.ref) |> Map.put(:task_pid, task.pid)
    }
  end

  defp maybe_interrupt_current(%{current_playback: %{guild_id: guild_id}} = state) do
    Logger.debug("Interrupting current playback in guild #{guild_id} for latest request")
    Voice.stop(guild_id)

    if Voice.playing?(guild_id) do
      state
      |> Map.put(:interrupting, true)
      |> schedule_interrupt_watchdog(guild_id, 1)
    else
      Logger.debug("Interrupt fast-path: playback stopped immediately in guild #{guild_id}")

      state
      |> clear_current_playback()
      |> maybe_start_pending()
    end
  end

  defp maybe_interrupt_current(state), do: state

  defp maintain_voice_connection(%{voice_channel: {guild_id, channel_id}} = state)
       when not is_nil(guild_id) and not is_nil(channel_id) do
    joined? = Voice.channel_id(guild_id) == to_string(channel_id)
    ready? = safe_voice_ready(guild_id)

    playing? =
      case safe_voice_playing(guild_id) do
        {:ok, value} ->
          value

        :error ->
          Logger.warning(
            "Voice playback status unavailable for guild #{guild_id}; continuing maintenance"
          )

          false
      end

    cond do
      playing? ->
        Logger.debug("Skipping voice maintenance while audio is playing in guild #{guild_id}")
        state

      joined? and ready? ->
        Logger.debug("Voice connection healthy for guild #{guild_id}")
        state

      joined? ->
        Logger.warning(
          "Voice session unready for guild #{guild_id} in channel #{channel_id}, attempting refresh"
        )

        attempt_voice_join(state, guild_id, channel_id, "refresh")

      true ->
        Logger.warning(
          "Voice channel mismatch for guild #{guild_id}, attempting to rejoin #{channel_id}"
        )

        attempt_voice_join(state, guild_id, channel_id, "rejoin")
    end
  end

  defp maintain_voice_connection(state) do
    Logger.debug("No voice channel set")
    state
  end

  defp attempt_voice_join(state, guild_id, channel_id, action) do
    Voice.join_channel(guild_id, channel_id)
    state
  rescue
    error ->
      Logger.error("Failed to #{action} voice channel: #{inspect(error)}")
      %{state | voice_channel: nil}
  end

  defp handle_playback_finished(state, guild_id) do
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

  defp maybe_start_pending(%{pending_request: nil} = state), do: state

  defp maybe_start_pending(state) do
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

  defp clear_current_playback(state) do
    cancel_playback_task(state.current_playback)

    state
    |> cancel_interrupt_watchdog()
    |> Map.merge(%{
      current_playback: nil,
      interrupting: false,
      interrupt_watchdog_attempt: 0
    })
  end

  defp reset_interrupt_state(state) do
    state
    |> cancel_interrupt_watchdog()
    |> Map.merge(%{interrupting: false, interrupt_watchdog_attempt: 0})
  end

  defp schedule_interrupt_watchdog(state, guild_id, attempt) do
    state = cancel_interrupt_watchdog(state)

    ref =
      Process.send_after(self(), {:interrupt_watchdog, guild_id, attempt}, @interrupt_watchdog_ms)

    %{state | interrupt_watchdog_ref: ref, interrupt_watchdog_attempt: attempt}
  end

  defp cancel_interrupt_watchdog(%{interrupt_watchdog_ref: nil} = state), do: state

  defp cancel_interrupt_watchdog(state) do
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

  defp safe_voice_ready(guild_id) do
    Voice.ready?(guild_id)
  rescue
    _ -> false
  end

  defp safe_voice_playing(guild_id) do
    {:ok, Voice.playing?(guild_id)}
  rescue
    _ -> :error
  end

  defp schedule_voice_check do
    Process.send_after(self(), :check_voice_connection, 30_000)
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
