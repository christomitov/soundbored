defmodule Soundboard.AudioPlayer do
  @moduledoc """
  Handles audio playback coordination.
  """

  use GenServer

  require Logger

  alias Soundboard.Accounts.User
  alias Soundboard.AudioPlayer.{Notifier, PlaybackQueue, SoundLibrary, VoiceSession}
  alias Soundboard.Discord.Handler.{AutoJoinPolicy, IdleTimeoutPolicy, VoicePresence}
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
      :interrupt_watchdog_attempt,
      :idle_timeout_ref,
      :now_playing
    ]

    @type t :: %__MODULE__{
            voice_channel: {String.t(), String.t()} | nil,
            current_playback: map() | nil,
            pending_request: map() | nil,
            interrupting: boolean() | nil,
            interrupt_watchdog_ref: reference() | nil,
            interrupt_watchdog_attempt: non_neg_integer() | nil,
            idle_timeout_ref: {reference(), reference()} | nil,
            now_playing: map() | nil
          }
  end

  @now_playing_grace_ms 2_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  def play_sound(sound_name, actor) do
    GenServer.cast(__MODULE__, {:play_sound, sound_name, actor})
  end

  def stop_sound do
    GenServer.cast(__MODULE__, :stop_sound)
  end

  @doc """
  Stops voice playback and clears the queue without broadcasting a voice-channel error
  when disconnected. Used by video playback before taking over Discord audio.
  """
  def clear_playback do
    GenServer.cast(__MODULE__, :clear_playback)
  end

  def set_voice_channel(guild_id, channel_id) do
    GenServer.cast(__MODULE__, {:set_voice_channel, guild_id, channel_id})
  end

  def last_user_left(guild_id) do
    GenServer.cast(__MODULE__, {:last_user_left, guild_id})
  end

  def user_joined_channel(guild_id) do
    GenServer.cast(__MODULE__, {:user_joined_channel, guild_id})
  end

  def playback_finished(guild_id) do
    GenServer.cast(__MODULE__, {:playback_finished, guild_id})
  end

  @doc false
  @spec sound_playing?() :: boolean()
  def sound_playing? do
    GenServer.call(__MODULE__, :sound_playing?)
  catch
    :exit, _ -> false
  end

  def current_voice_channel do
    {:ok, GenServer.call(__MODULE__, :get_voice_channel)}
  rescue
    error -> {:error, {:voice_channel_unavailable, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:voice_channel_unavailable, reason}}
  end

  @doc """
  Returns the bot's current voice channel, auto-joining the actor's channel when
  `AUTO_JOIN=play` and the bot is not connected yet.
  """
  @spec ensure_voice_channel(term()) ::
          {:ok, {String.t(), String.t()}} | {:error, String.t()}
  def ensure_voice_channel(actor) do
    GenServer.call(__MODULE__, {:ensure_voice_channel, actor}, 15_000)
  rescue
    error ->
      {:error, "Voice channel unavailable: #{Exception.message(error)}"}
  catch
    :exit, reason ->
      {:error, "Voice channel unavailable: #{inspect(reason)}"}
  end

  def set_now_playing(payload) when is_map(payload) do
    GenServer.cast(__MODULE__, {:set_now_playing, payload})
  end

  def clear_now_playing do
    GenServer.cast(__MODULE__, :clear_now_playing)
  end

  def now_playing do
    GenServer.call(__MODULE__, :now_playing)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
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
         interrupt_watchdog_attempt: 0,
         idle_timeout_ref: nil,
         now_playing: nil
     }}
  end

  @impl true
  def handle_cast({:set_voice_channel, guild_id, channel_id}, state) do
    next_state =
      case VoiceSession.normalize_channel(guild_id, channel_id) do
        nil ->
          Notifier.playback_stopped()

          state
          |> PlaybackQueue.clear_all()
          |> cancel_idle_timeout()
          |> Map.put(:voice_channel, nil)
          |> Map.put(:now_playing, nil)

        voice_channel ->
          new_state =
            state
            |> cancel_idle_timeout()
            |> Map.put(:voice_channel, voice_channel)

          if AutoJoinPolicy.mode() == :play, do: schedule_idle_timeout(new_state), else: new_state
      end

    {:noreply, next_state}
  end

  def handle_cast({:set_now_playing, payload}, state) do
    {:noreply, %{state | now_playing: payload}}
  end

  def handle_cast(:clear_now_playing, state) do
    {:noreply, %{state | now_playing: nil}}
  end

  def handle_cast(:stop_sound, %{voice_channel: {guild_id, _channel_id}} = state) do
    Soundboard.VideoPlayer.interrupt()
    Voice.stop(guild_id)
    Notifier.playback_stopped()

    {:noreply, PlaybackQueue.clear_all(state)}
  end

  def handle_cast(:stop_sound, state) do
    Soundboard.VideoPlayer.interrupt()
    Notifier.error("Bot is not connected to a voice channel")
    {:noreply, state}
  end

  def handle_cast(:clear_playback, %{voice_channel: {guild_id, _channel_id}} = state) do
    Voice.stop(guild_id)
    Notifier.playback_stopped()

    {:noreply,
     state
     |> PlaybackQueue.clear_all()
     |> Map.put(:now_playing, nil)}
  end

  def handle_cast(:clear_playback, state) do
    {:noreply, Map.put(state, :now_playing, nil)}
  end

  def handle_cast({:playback_finished, guild_id}, state) do
    sound_boundary? =
      match?(%{guild_id: ^guild_id}, state.current_playback) or
        (state.interrupting and match?({^guild_id, _}, state.voice_channel) and
           not is_nil(state.pending_request))

    next_state = PlaybackQueue.handle_playback_finished(state, guild_id)

    if sound_boundary? do
      maybe_resume_video_audio(next_state)
    else
      # Live YouTube audio is continuous — an ffmpeg blip must not end the session.
      # VOD end-of-file should advance the queue while actively playing.
      if Soundboard.VideoPlayer.playing?() and not Soundboard.VideoPlayer.livestreaming?() do
        Soundboard.VideoPlayer.notify_media_ended()
      end
    end

    {:noreply, next_state}
  end

  def handle_cast({:play_sound, sound_name, actor}, %{voice_channel: nil} = state) do
    if AutoJoinPolicy.mode() == :play do
      case try_auto_join(actor) do
        {:ok, {guild_id, channel_id}} ->
          new_state =
            state
            |> Map.put(:voice_channel, {guild_id, channel_id})
            |> schedule_idle_timeout()

          do_play_sound(sound_name, actor, new_state)

        :not_found ->
          Notifier.error("Bot is not connected to a voice channel. Use !join in Discord first.")
          {:noreply, state}
      end
    else
      Notifier.error("Bot is not connected to a voice channel. Use !join in Discord first.")
      {:noreply, state}
    end
  end

  def handle_cast({:play_sound, sound_name, actor}, state) do
    do_play_sound(sound_name, actor, state)
  end

  def handle_cast({:last_user_left, guild_id}, %{voice_channel: {guild_id, _}} = state) do
    case AutoJoinPolicy.mode() do
      mode when mode in [:presence, :play] ->
        Logger.info("Last user left (#{mode} mode); leaving guild #{guild_id}")
        safely_leave(guild_id)
        Notifier.playback_stopped()

        new_state =
          state
          |> cancel_idle_timeout()
          |> PlaybackQueue.clear_all()
          |> Map.put(:voice_channel, nil)
          |> Map.put(:now_playing, nil)

        {:noreply, new_state}

      false ->
        Logger.info("Last user left (false mode); starting idle timer")
        {:noreply, reset_idle_timeout(state)}
    end
  end

  def handle_cast({:last_user_left, _guild_id}, state), do: {:noreply, state}

  def handle_cast({:user_joined_channel, _guild_id}, state) do
    {:noreply, cancel_idle_timeout(state)}
  end

  @impl true
  def handle_call(:get_voice_channel, _from, state) do
    {:reply, state.voice_channel, state}
  end

  def handle_call({:ensure_voice_channel, actor}, _from, state) do
    case state.voice_channel do
      {_, _} = channel ->
        new_state =
          if AutoJoinPolicy.mode() == :play, do: reset_idle_timeout(state), else: state

        {:reply, {:ok, channel}, new_state}

      nil ->
        ensure_missing_voice_channel(actor, state)
    end
  end

  def handle_call(:now_playing, _from, state) do
    {:reply, active_now_playing(state.now_playing), state}
  end

  def handle_call(:sound_playing?, _from, state) do
    active? =
      not is_nil(state.current_playback) or not is_nil(state.pending_request) or
        state.interrupting == true

    {:reply, active?, state}
  end

  defp ensure_missing_voice_channel(actor, state) do
    if AutoJoinPolicy.mode() == :play do
      auto_join_voice_channel(actor, state)
    else
      {:reply, {:error, "Bot is not connected to a voice channel. Use !join in Discord first."},
       state}
    end
  end

  defp auto_join_voice_channel(actor, state) do
    case try_auto_join(actor) do
      {:ok, channel} ->
        new_state =
          state
          |> Map.put(:voice_channel, channel)
          |> schedule_idle_timeout()

        {:reply, {:ok, channel}, new_state}

      :not_found ->
        {:reply,
         {:error,
          "Bot is not connected to a voice channel. Join a Discord voice channel and try again (or use !join)."},
         state}
    end
  end

  @impl true
  def handle_info(
        {:idle_timeout, token},
        %{idle_timeout_ref: {_ref, token}, voice_channel: {guild_id, _}} = state
      ) do
    Logger.info("Voice idle timeout in guild #{guild_id}; leaving channel")
    safely_leave(guild_id)
    Notifier.playback_stopped()

    new_state =
      %{state | idle_timeout_ref: nil, now_playing: nil}
      |> PlaybackQueue.clear_all()
      |> Map.put(:voice_channel, nil)

    {:noreply, new_state}
  end

  def handle_info({:idle_timeout, _stale_token}, state), do: {:noreply, state}

  @impl true
  def handle_info(:check_voice_connection, state) do
    schedule_voice_check()
    {:noreply, VoiceSession.maintain_connection(state)}
  end

  @impl true
  def handle_info({ref, result}, %{current_playback: %{task_ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    next_state = PlaybackQueue.handle_task_result(state, result)
    maybe_resume_video_audio(next_state)
    {:noreply, next_state}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current_playback: %{task_ref: ref}} = state
      ) do
    next_state = PlaybackQueue.handle_task_down(state, reason)
    maybe_resume_video_audio(next_state)
    {:noreply, next_state}
  end

  @impl true
  def handle_info({:interrupt_watchdog, guild_id, attempt}, state) do
    next_state =
      PlaybackQueue.handle_interrupt_watchdog(
        state,
        guild_id,
        attempt,
        @interrupt_watchdog_max_attempts,
        @interrupt_watchdog_ms
      )

    maybe_resume_video_audio(next_state)
    {:noreply, next_state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp do_play_sound(sound_name, actor, %{voice_channel: voice_channel} = state) do
    case PlaybackQueue.build_request(voice_channel, sound_name, actor) do
      {:ok, request} ->
        new_state =
          if AutoJoinPolicy.mode() == :play, do: reset_idle_timeout(state), else: state

        {:noreply, enqueue_sound_request(new_state, request)}

      {:error, reason} ->
        Notifier.error(reason)
        {:noreply, state}
    end
  end

  defp enqueue_sound_request(state, request) do
    overlay_video? =
      is_nil(state.current_playback) and not state.interrupting and
        Soundboard.VideoPlayer.playing?()

    if overlay_video? and Soundboard.VideoPlayer.suspend_discord_audio() == :suspended do
      PlaybackQueue.await_external_interrupt(state, request, @interrupt_watchdog_ms)
    else
      PlaybackQueue.enqueue(state, request, @interrupt_watchdog_ms)
    end
  end

  defp maybe_resume_video_audio(%State{
         current_playback: nil,
         pending_request: nil,
         interrupting: false
       }) do
    if Soundboard.VideoPlayer.playing?() do
      Soundboard.VideoPlayer.resume_discord_audio()
    else
      Soundboard.VideoPlayer.sound_playback_idle()
    end

    :ok
  end

  defp maybe_resume_video_audio(_state), do: :ok

  defp try_auto_join(actor) do
    case actor_discord_id(actor) do
      nil -> :not_found
      discord_id -> find_and_join_voice(discord_id)
    end
  end

  defp find_and_join_voice(discord_id) do
    case VoicePresence.find_user_voice_channel(discord_id) do
      {:ok, {guild_id, channel_id}} ->
        Logger.info(
          "Auto-joining channel #{channel_id} in guild #{guild_id} for user #{discord_id}"
        )

        Voice.join_channel(guild_id, channel_id)
        {:ok, {guild_id, channel_id}}

      :not_found ->
        Logger.info("User #{discord_id} not in a voice channel; skipping auto-join")
        :not_found
    end
  rescue
    error ->
      Logger.warning("Auto-join failed: #{inspect(error)}")
      :not_found
  end

  defp safely_leave(guild_id) do
    Voice.leave_channel(guild_id)
  rescue
    error -> Logger.warning("Voice leave failed: #{inspect(error)}")
  end

  defp actor_discord_id(%User{discord_id: id}) when is_binary(id) and id != "", do: id
  defp actor_discord_id(%{discord_id: id}) when is_binary(id) and id != "", do: id
  defp actor_discord_id(_), do: nil

  defp schedule_idle_timeout(state) do
    case IdleTimeoutPolicy.timeout_ms() do
      nil ->
        state

      ms ->
        token = make_ref()
        ref = Process.send_after(self(), {:idle_timeout, token}, ms)
        %{state | idle_timeout_ref: {ref, token}}
    end
  end

  defp cancel_idle_timeout(%{idle_timeout_ref: nil} = state), do: state

  defp cancel_idle_timeout(%{idle_timeout_ref: {ref, _token}} = state) do
    Process.cancel_timer(ref)
    %{state | idle_timeout_ref: nil}
  end

  defp reset_idle_timeout(state) do
    state |> cancel_idle_timeout() |> schedule_idle_timeout()
  end

  defp schedule_voice_check do
    if Application.get_env(:soundboard, __MODULE__, [])[:voice_maintenance_enabled] != false do
      Process.send_after(self(), :check_voice_connection, 30_000)
    end
  end

  defp active_now_playing(nil), do: nil

  defp active_now_playing(%{duration_ms: duration_ms, started_at: started_at} = payload)
       when is_integer(duration_ms) and duration_ms > 0 and is_integer(started_at) do
    if System.system_time(:millisecond) > started_at + duration_ms + @now_playing_grace_ms do
      nil
    else
      payload
    end
  end

  defp active_now_playing(payload) when is_map(payload), do: payload
  defp active_now_playing(_), do: nil
end
