defmodule Soundboard.VideoPlayer do
  @moduledoc """
  Coordinates YouTube ingest, HLS remux, synced web playback, Discord audio,
  and an up-next queue.
  """

  use GenServer

  require Logger

  alias Soundboard.{Accounts, Stats}
  alias Soundboard.Accounts.User
  alias Soundboard.AudioPlayer
  alias Soundboard.AudioPlayer.Notifier
  alias Soundboard.PubSubTopics
  alias Soundboard.Video.{HlsRemux, LiveHls, SessionsPath}
  alias Soundboard.VideoPlayer.DiscordAudio
  alias Soundboard.YouTube.Extractor

  defmodule Session do
    @moduledoc false
    defstruct [
      :id,
      :youtube_id,
      :title,
      :thumbnail_url,
      :url,
      :media_path,
      :stream_url,
      :hls_url,
      :host_user_id,
      :host_username,
      :duration_ms,
      :position_ms,
      :updated_at,
      :status,
      :error,
      :remux_mode,
      :live_pid,
      live?: false,
      playing?: false
    ]

    @type status :: :fetching | :remuxing | :ready | :error
    @type t :: %__MODULE__{
            id: String.t() | nil,
            youtube_id: String.t() | nil,
            title: String.t() | nil,
            thumbnail_url: String.t() | nil,
            url: String.t() | nil,
            media_path: String.t() | nil,
            stream_url: String.t() | nil,
            hls_url: String.t() | nil,
            host_user_id: integer() | nil,
            host_username: String.t() | nil,
            duration_ms: non_neg_integer() | nil,
            position_ms: non_neg_integer(),
            updated_at: integer() | nil,
            status: status() | nil,
            error: String.t() | nil,
            remux_mode: :transcode | :live | nil,
            live_pid: pid() | nil,
            live?: boolean(),
            playing?: boolean()
          }
  end

  defmodule QueueItem do
    @moduledoc false
    defstruct [
      :id,
      :url,
      :youtube_id,
      :title,
      :thumbnail_url,
      :queued_by_user_id,
      :queued_by_username,
      :duration_ms,
      :media_path,
      :stream_url,
      :remux_mode,
      :prefetch_ref,
      :prefetch_pid,
      :progress_percent,
      :error,
      live?: false,
      prefetch_status: :pending
    ]

    @type prefetch_status :: :pending | :fetching | :remuxing | :ready | :error

    @type t :: %__MODULE__{
            id: String.t(),
            url: String.t(),
            youtube_id: String.t() | nil,
            title: String.t() | nil,
            thumbnail_url: String.t() | nil,
            queued_by_user_id: integer(),
            queued_by_username: String.t(),
            duration_ms: non_neg_integer() | nil,
            media_path: String.t() | nil,
            stream_url: String.t() | nil,
            remux_mode: :transcode | nil,
            prefetch_ref: reference() | nil,
            prefetch_pid: pid() | nil,
            progress_percent: 0..100 | nil,
            error: String.t() | nil,
            live?: boolean(),
            prefetch_status: prefetch_status()
          }
  end

  defmodule State do
    @moduledoc false
    defstruct session: nil,
              queue: [],
              task_ref: nil,
              task_pid: nil,
              end_timer_ref: nil,
              live_monitor_ref: nil
  end

  # —— Public API ——

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)
  end

  @doc """
  Plays immediately when idle; otherwise appends to the up-next queue.
  Returns `{:ok, :playing}` or `{:ok, :queued}`.
  """
  @spec play(String.t(), User.t()) :: {:ok, :playing | :queued} | {:error, String.t()}
  def play(url, %User{} = user) when is_binary(url) do
    sound_playing? = AudioPlayer.sound_playing?()
    GenServer.call(__MODULE__, {:play, url, user, sound_playing?}, 5_000)
  catch
    :exit, _ -> {:error, "Video player is unavailable"}
  end

  @spec stop() :: :ok
  def stop, do: GenServer.cast(__MODULE__, :stop)

  @doc """
  Clears any active video session and queue without touching Discord voice.
  Used by the explicit stop-all action.
  """
  @spec interrupt() :: :ok
  def interrupt, do: GenServer.cast(__MODULE__, :interrupt)

  @doc "Temporarily stops Discord video audio without changing the video session or queue."
  @spec suspend_discord_audio() :: :suspended | :noop
  def suspend_discord_audio do
    GenServer.call(__MODULE__, :suspend_discord_audio)
  catch
    :exit, _ -> :noop
  end

  @doc "Restarts Discord video audio at the session's current synchronized position."
  @spec resume_discord_audio() :: :ok
  def resume_discord_audio, do: GenServer.cast(__MODULE__, :resume_discord_audio)

  @doc "Starts a deferred queued video after soundboard playback becomes idle."
  @spec sound_playback_idle() :: :ok
  def sound_playback_idle, do: GenServer.cast(__MODULE__, :sound_playback_idle)

  @spec seek(User.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def seek(%User{} = user, position_ms) when is_integer(position_ms) and position_ms >= 0 do
    GenServer.call(__MODULE__, {:seek, user, position_ms})
  catch
    :exit, _ -> {:error, "Video player is unavailable"}
  end

  @spec pause(User.t()) :: :ok | {:error, String.t()}
  def pause(%User{} = user), do: GenServer.call(__MODULE__, {:pause, user})

  @spec resume(User.t()) :: :ok | {:error, String.t()}
  def resume(%User{} = user), do: GenServer.call(__MODULE__, {:resume, user})

  @spec skip(User.t()) :: :ok | {:error, String.t()}
  def skip(%User{} = user), do: GenServer.call(__MODULE__, {:skip, user})

  @spec play_queued(User.t(), String.t()) :: :ok | {:error, String.t()}
  def play_queued(%User{} = user, item_id) when is_binary(item_id) do
    GenServer.call(__MODULE__, {:play_queued, user, item_id})
  end

  @spec remove_from_queue(User.t(), String.t()) :: :ok | {:error, String.t()}
  def remove_from_queue(%User{} = user, item_id) when is_binary(item_id) do
    GenServer.call(__MODULE__, {:remove_from_queue, user, item_id})
  end

  @spec clear_queue(User.t()) :: :ok | {:error, String.t()}
  def clear_queue(%User{} = user), do: GenServer.call(__MODULE__, {:clear_queue, user})

  @spec session() :: map() | nil
  def session do
    GenServer.call(__MODULE__, :session)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  @spec queue() :: [map()]
  def queue do
    GenServer.call(__MODULE__, :queue)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @spec live?() :: boolean()
  def live? do
    case session() do
      %{status: status} when status in [:fetching, :remuxing, :ready] -> true
      _ -> false
    end
  end

  @doc """
  True when a ready video session is actively playing (not paused).
  """
  @spec playing?() :: boolean()
  def playing? do
    case session() do
      %{status: :ready, playing?: true} -> true
      _ -> false
    end
  end

  @doc """
  True when a ready live (non-VOD) video session is actively playing.
  """
  @spec livestreaming?() :: boolean()
  def livestreaming? do
    case session() do
      %{status: :ready, playing?: true, live?: true} -> true
      _ -> false
    end
  end

  @doc "Advances playback when the current Discord video media source reaches its end."
  @spec notify_media_ended(String.t() | nil) :: :ok
  def notify_media_ended(session_id \\ nil)
  def notify_media_ended(nil), do: GenServer.cast(__MODULE__, :media_ended)

  def notify_media_ended(session_id) when is_binary(session_id) do
    GenServer.cast(__MODULE__, {:media_ended, session_id})
  end

  @spec public_session(Session.t() | nil) :: map() | nil
  def public_session(nil), do: nil

  def public_session(%Session{} = session) do
    %{
      id: session.id,
      youtube_id: session.youtube_id,
      title: session.title,
      thumbnail_url: Map.get(session, :thumbnail_url),
      url: session.url,
      hls_url: session.hls_url,
      host_user_id: session.host_user_id,
      host_username: session.host_username,
      duration_ms: session.duration_ms,
      position_ms: estimated_position_ms(session),
      updated_at: session.updated_at,
      status: session.status,
      error: session.error,
      remux_mode: session.remux_mode,
      live?: session.live? == true,
      playing?: session.playing?
    }
  end

  @spec public_queue_item(QueueItem.t()) :: map()
  def public_queue_item(%QueueItem{} = item) do
    %{
      id: item.id,
      url: item.url,
      youtube_id: item.youtube_id,
      title: item.title,
      thumbnail_url: Map.get(item, :thumbnail_url) || Extractor.thumbnail_url(item.youtube_id),
      queued_by_user_id: item.queued_by_user_id,
      queued_by_username: item.queued_by_username,
      prefetch_status: item.prefetch_status,
      progress_percent: item.progress_percent,
      live?: item.live? == true,
      error: item.error
    }
  end

  # —— GenServer ——

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:play, url, user, sound_playing?}, _from, state) do
    url = String.trim(url)

    cond do
      not Extractor.valid_url?(url) ->
        {:reply, {:error, "That doesn't look like a valid YouTube URL."}, state}

      not Extractor.available?() ->
        {:reply, {:error, "YouTube playback is not available (yt-dlp not installed)."}, state}

      busy?(state.session) or sound_playing? ->
        {:reply, {:ok, :queued}, enqueue_video(state, url, user)}

      true ->
        state = start_playback(state, url, user)
        {:reply, {:ok, :playing}, state}
    end
  end

  def handle_call(:session, _from, state) do
    {:reply, public_session(state.session), state}
  end

  def handle_call(:queue, _from, state) do
    {:reply, Enum.map(state.queue, &public_queue_item/1), state}
  end

  def handle_call(
        :suspend_discord_audio,
        _from,
        %{session: %Session{status: :ready, playing?: true}} = state
      ) do
    # This call originates from AudioPlayer, so avoid its fallback channel
    # lookup here (which would synchronously call back into the caller).
    DiscordAudio.stop_tracked()
    {:reply, :suspended, state}
  end

  def handle_call(:suspend_discord_audio, _from, state), do: {:reply, :noop, state}

  def handle_call({:seek, user, position_ms}, _from, state) do
    with {:ok, session} <- require_host(state.session, user),
         {:ok, session} <- require_ready(session) do
      {:reply, :ok, seek_session(session, position_ms, state)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:pause, user}, _from, state) do
    with {:ok, session} <- require_host(state.session, user),
         {:ok, session} <- require_ready(session) do
      position_ms = estimated_position_ms(session)

      session = %{
        session
        | position_ms: position_ms,
          updated_at: now_ms(),
          playing?: false
      }

      # Persist paused state before stopping Discord so a concurrent
      # playback_finished event cannot advance the queue.
      state = %{state | session: session} |> cancel_end_timer()
      DiscordAudio.stop()
      clear_now_playing()
      broadcast_sync(session)
      broadcast_state(session)
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:resume, user}, _from, state) do
    with {:ok, session} <- require_host(state.session, user),
         {:ok, session} <- require_ready(session) do
      session = %{session | playing?: true}
      # Restart Discord first, then stamp the clock and push sync so the
      # browser seeks to the same point Discord is about to play.
      _ = maybe_restart_discord(session)
      session = %{session | updated_at: now_ms()}

      state = %{state | session: session} |> reschedule_end_timer()
      publish_now_playing(session)
      broadcast_state(session)
      broadcast_sync(session)
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:skip, user}, _from, state) do
    case require_host(state.session, user) do
      {:ok, _session} -> {:reply, :ok, advance_queue(state)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:play_queued, user, item_id}, _from, state) do
    case require_queue_control(state, user) do
      {:ok, _} -> handle_play_queued(item_id, state)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove_from_queue, user, item_id}, _from, state) do
    case require_queue_control(state, user) do
      {:ok, _} -> remove_queued_item(item_id, state)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:clear_queue, user}, _from, state) do
    case require_queue_control(state, user) do
      {:ok, _} ->
        Enum.each(state.queue, &cancel_and_cleanup_prefetch/1)
        broadcast_queue([])
        {:reply, :ok, %{state | queue: []}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:stop, state) do
    state =
      state
      |> demonitor_live()
      |> cancel_task()
      |> cancel_end_timer()

    DiscordAudio.stop()
    clear_now_playing()
    cleanup_session(state.session)
    Enum.each(state.queue, &cancel_and_cleanup_prefetch/1)
    PubSubTopics.broadcast_video_stopped()
    broadcast_queue([])
    {:noreply, %{state | session: nil, queue: []}}
  end

  def handle_cast(:interrupt, state) do
    had_session? = match?(%Session{}, state.session)
    had_queue? = state.queue != []

    state =
      state
      |> demonitor_live()
      |> cancel_task()
      |> cancel_end_timer()

    DiscordAudio.stop()
    clear_now_playing()
    cleanup_session(state.session)
    Enum.each(state.queue, &cancel_and_cleanup_prefetch/1)

    if had_session? or had_queue? do
      PubSubTopics.broadcast_video_stopped()
      broadcast_queue([])
    end

    {:noreply, %{state | session: nil, queue: []}}
  end

  def handle_cast(:media_ended, %{session: %Session{status: status, playing?: true}} = state)
      when status in [:ready, :error] do
    {:noreply, advance_queue(state)}
  end

  def handle_cast(:media_ended, state), do: {:noreply, state}

  def handle_cast(:sound_playback_idle, state) do
    if not busy?(state.session) and state.queue != [] do
      {:noreply, advance_queue(state)}
    else
      {:noreply, state}
    end
  end

  # Browsers emit `pause` immediately before `ended`. The pause request can be
  # processed first and mark the session as not playing, so an explicit ended
  # notification is authoritative as long as it names the current ready session.
  def handle_cast(
        {:media_ended, session_id},
        %{session: %Session{id: session_id, status: :ready}} = state
      ) do
    {:noreply, advance_queue(state)}
  end

  def handle_cast({:media_ended, _stale_session_id}, state), do: {:noreply, state}

  def handle_cast(
        :resume_discord_audio,
        %{session: %Session{status: :ready, playing?: true} = session} = state
      ) do
    position_ms = estimated_position_ms(session)
    position_ms = if is_integer(position_ms), do: position_ms, else: session.position_ms || 0
    session = %{session | position_ms: position_ms}
    _ = maybe_restart_discord(session)
    session = %{session | updated_at: now_ms()}

    state = %{state | session: session} |> reschedule_end_timer()
    publish_now_playing(session)
    broadcast_state(session)
    broadcast_sync(session)
    {:noreply, state}
  end

  def handle_cast(:resume_discord_audio, state), do: {:noreply, state}

  @impl true
  def handle_info({ref, result}, %{task_ref: ref, session: %Session{} = session} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | task_ref: nil, task_pid: nil}

    next_state =
      state
      |> handle_playback_result(session, normalize_ingest_result(result))
      |> maybe_start_next_prefetch()

    {:noreply, next_state}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    case find_prefetch_item(state.queue, ref) do
      nil ->
        {:noreply, state}

      item ->
        Process.demonitor(ref, [:flush])

        next_state =
          state
          |> handle_prefetch_result(item, result)
          |> maybe_start_next_prefetch()

        {:noreply, next_state}
    end
  end

  def handle_info(
        {:video_ingest_status, session_id, :remuxing},
        %{session: %Session{id: session_id} = session} = state
      ) do
    session = %{session | status: :remuxing, updated_at: now_ms()}
    broadcast_state(session)
    {:noreply, %{state | session: session}}
  end

  def handle_info({:video_ingest_status, _session_id, _status}, state), do: {:noreply, state}

  def handle_info({:video_prefetch_meta, item_id, meta}, state) do
    queue =
      update_queue_item(state.queue, item_id, fn item ->
        %{
          item
          | title: Map.get(meta, :title) || item.title,
            thumbnail_url: Map.get(meta, :thumbnail_url) || Map.get(item, :thumbnail_url),
            youtube_id: Map.get(meta, :youtube_id) || item.youtube_id,
            duration_ms: Map.get(meta, :duration_ms) || item.duration_ms,
            live?: Map.get(meta, :live?, item.live?) == true,
            progress_percent: max(item.progress_percent || 0, 30)
        }
      end)

    broadcast_queue(queue)
    {:noreply, %{state | queue: queue}}
  end

  def handle_info({:video_prefetch_status, item_id, :remuxing}, state) do
    queue =
      update_queue_item(state.queue, item_id, fn item ->
        %{item | prefetch_status: :remuxing, progress_percent: 75}
      end)

    broadcast_queue(queue)
    {:noreply, %{state | queue: queue}}
  end

  def handle_info({:video_ended, session_id}, %{session: %Session{id: session_id}} = state) do
    {:noreply, advance_queue(%{state | end_timer_ref: nil})}
  end

  def handle_info({:video_ended, _stale}, state), do: {:noreply, state}

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{task_ref: ref, session: session} = state
      ) do
    message = "Video ingest failed: #{inspect(reason)}"
    Logger.error(message)

    session =
      case session do
        %Session{} = s ->
          s = %{s | status: :error, error: message, playing?: false, updated_at: now_ms()}
          broadcast_state(s)
          PubSubTopics.broadcast_video_error(message)
          s

        _ ->
          nil
      end

    state = %{state | session: session, task_ref: nil, task_pid: nil}
    {:noreply, advance_queue_after_error(state)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{live_monitor_ref: ref, session: %Session{live?: true}} = state
      ) do
    Logger.info("Live HLS holder exited for session #{state.session.id}")
    {:noreply, advance_queue(demonitor_live(%{state | live_monitor_ref: nil}))}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    case find_prefetch_item(state.queue, ref) do
      nil ->
        {:noreply, state}

      item ->
        message = "Queue prefetch failed: #{inspect(reason)}"
        Logger.warning(message)

        queue =
          update_queue_item(state.queue, item.id, fn item ->
            %{
              item
              | prefetch_status: :error,
                error: message,
                prefetch_ref: nil,
                prefetch_pid: nil
            }
          end)

        broadcast_queue(queue)
        {:noreply, maybe_start_next_prefetch(%{state | queue: queue})}
    end
  end

  def handle_info({:live_hls_stopped, pid}, %{session: %Session{live_pid: pid} = session} = state) do
    Logger.info("Live HLS ended for session #{session.id}")
    {:noreply, advance_queue(demonitor_live(state))}
  end

  def handle_info({:live_hls_stopped, _pid}, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # —— Internals ——

  defp busy?(%Session{status: status}) when status in [:fetching, :remuxing, :ready], do: true
  defp busy?(_), do: false

  defp enqueue_video(state, url, user) do
    {:ok, youtube_id} = Extractor.youtube_id(url)

    item = %QueueItem{
      id: generate_session_id(),
      url: url,
      youtube_id: youtube_id,
      thumbnail_url: Extractor.thumbnail_url(youtube_id),
      title: nil,
      queued_by_user_id: user.id,
      queued_by_username: user.username,
      progress_percent: 5,
      prefetch_status: :pending
    }

    queue = state.queue ++ [item]
    broadcast_queue(queue)

    %{state | queue: queue}
    |> maybe_start_next_prefetch()
  end

  defp initial_position_ms(session, extraction, true = _live?) do
    # Explicit timestamps on a live URL still seek into DVR when provided.
    requested = session.position_ms || 0

    if requested > 0 do
      clamp_position(requested, extraction.duration_ms)
    else
      # Join near the live edge of the DVR window.
      clamp_position(extraction.duration_ms || 0, extraction.duration_ms)
    end
  end

  defp initial_position_ms(session, extraction, _live?) do
    clamp_position(session.position_ms || 0, extraction.duration_ms)
  end

  defp seek_session(%Session{live?: true} = session, _position_ms, state) do
    # Live Discord audio is the upstream stream — scrubbing only moves the
    # browser DVR window. Restarting Discord on every seek caused a kill loop.
    broadcast_sync(session)
    broadcast_state(session)
    state
  end

  defp seek_session(%Session{} = session, position_ms, state) do
    position_ms = clamp_position(position_ms, session.duration_ms)
    session = %{session | position_ms: position_ms}

    # Keep paused seeks paused. When playing, restart Discord before stamping
    # the shared clock.
    if session.playing?, do: maybe_restart_discord(session)
    session = %{session | updated_at: now_ms()}

    state =
      if session.playing? do
        %{state | session: session} |> reschedule_end_timer()
      else
        %{state | session: session} |> cancel_end_timer()
      end

    if session.playing?, do: publish_now_playing(session)
    broadcast_sync(session)
    broadcast_state(session)
    state
  end

  defp start_playback(state, url, user) do
    start_playback(state, url, user, generate_session_id(), %{})
  end

  defp start_playback(state, url, user, session_id, metadata) do
    state =
      state
      |> demonitor_live()
      |> cancel_task()
      |> cancel_end_timer()

    cleanup_session(state.session)
    AudioPlayer.clear_playback()

    start_ms = Extractor.start_offset_ms(url)

    session = %Session{
      id: session_id,
      url: url,
      youtube_id: Map.get(metadata, :youtube_id),
      title: Map.get(metadata, :title),
      thumbnail_url: Map.get(metadata, :thumbnail_url),
      duration_ms: Map.get(metadata, :duration_ms),
      host_user_id: user.id,
      host_username: user.username,
      position_ms: start_ms,
      updated_at: now_ms(),
      status: :fetching,
      live?: false,
      playing?: false
    }

    parent = self()

    task =
      Task.Supervisor.async_nolink(Soundboard.AudioTaskSupervisor, fn ->
        ingest(url, session_id, parent)
      end)

    broadcast_state(session)
    %{state | session: session, task_ref: task.ref, task_pid: task.pid}
  end

  defp advance_queue(state) do
    case state.queue do
      [%QueueItem{} = item | rest] ->
        activate_queue_item(state, item, rest)

      [] ->
        state =
          state
          |> demonitor_live()
          |> cancel_task()
          |> cancel_end_timer()

        DiscordAudio.stop()
        cleanup_session(state.session)
        clear_now_playing()
        PubSubTopics.broadcast_video_stopped()
        broadcast_queue([])
        %{state | session: nil, queue: []}
    end
  end

  defp activate_queue_item(state, item, rest) do
    rest =
      if queue_item_needs_fresh_ingest?(item) do
        suspend_active_prefetches(rest)
      else
        rest
      end

    state =
      state
      |> demonitor_live()
      |> cancel_task()
      |> cancel_end_timer()

    DiscordAudio.stop()
    cleanup_session(state.session)
    broadcast_queue(rest)

    %{state | session: nil, queue: rest}
    |> play_queue_item(item)
    |> maybe_start_next_prefetch()
  end

  defp advance_queue_after_error(%{queue: []} = state), do: state

  defp advance_queue_after_error(state) do
    advance_queue(state)
  end

  defp handle_play_queued(item_id, state) do
    case Enum.split_while(state.queue, &(&1.id != item_id)) do
      {skipped, [%QueueItem{} = selected | rest]} ->
        Enum.each(skipped, &cancel_and_cleanup_prefetch/1)
        {:reply, :ok, activate_queue_item(state, selected, rest)}

      {_skipped, []} ->
        {:reply, {:error, "That video is no longer in the queue"}, state}
    end
  end

  defp remove_queued_item(item_id, state) do
    {removed, queue} = Enum.split_with(state.queue, &(&1.id == item_id))
    Enum.each(removed, &cancel_and_cleanup_prefetch/1)
    broadcast_queue(queue)
    {:reply, :ok, maybe_start_next_prefetch(%{state | queue: queue})}
  end

  defp play_queue_item(
         state,
         %QueueItem{prefetch_status: :ready, live?: false, media_path: path} = item
       )
       when is_binary(path) do
    user = %User{id: item.queued_by_user_id, username: item.queued_by_username}
    activate_ready_vod(state, item, user)
  end

  defp play_queue_item(
         state,
         %QueueItem{prefetch_status: :ready, live?: true, stream_url: url} = item
       )
       when is_binary(url) do
    user = %User{id: item.queued_by_user_id, username: item.queued_by_username}
    start_live_from_prefetch(state, item, user)
  end

  defp play_queue_item(
         state,
         %QueueItem{prefetch_status: status, live?: false, prefetch_ref: ref} = item
       )
       when status in [:fetching, :remuxing] and is_reference(ref) do
    user = %User{id: item.queued_by_user_id, username: item.queued_by_username}
    adopt_in_flight_prefetch(state, item, user)
  end

  defp play_queue_item(state, %QueueItem{} = item) do
    cancel_prefetch_task(item)
    SessionsPath.cleanup_session(item.id)
    user = %User{id: item.queued_by_user_id, username: item.queued_by_username}
    start_playback(state, item.url, user, item.id, item)
  end

  defp queue_item_needs_fresh_ingest?(%QueueItem{} = item) do
    ready? =
      item.prefetch_status == :ready and
        ((item.live? != true and is_binary(item.media_path)) or
           (item.live? == true and is_binary(item.stream_url)))

    adoptable? =
      item.prefetch_status in [:fetching, :remuxing] and item.live? != true and
        is_reference(item.prefetch_ref)

    not ready? and not adoptable?
  end

  defp suspend_active_prefetches(queue) do
    Enum.map(queue, fn item ->
      if item.prefetch_status in [:fetching, :remuxing] and
           (is_reference(item.prefetch_ref) or is_pid(item.prefetch_pid)) do
        cancel_prefetch_task(item)
        SessionsPath.cleanup_session(item.id)

        %{
          item
          | media_path: nil,
            stream_url: nil,
            remux_mode: nil,
            prefetch_ref: nil,
            prefetch_pid: nil,
            progress_percent: 5,
            prefetch_status: :pending,
            error: nil
        }
      else
        item
      end
    end)
  end

  defp activate_ready_vod(state, item, user) do
    AudioPlayer.clear_playback()
    start_ms = Extractor.start_offset_ms(item.url)

    session = %Session{
      id: item.id,
      url: item.url,
      youtube_id: item.youtube_id,
      title: item.title,
      thumbnail_url: Map.get(item, :thumbnail_url),
      media_path: item.media_path,
      stream_url: nil,
      duration_ms: item.duration_ms,
      hls_url: "/video/sessions/#{item.id}/index.m3u8",
      remux_mode: item.remux_mode,
      host_user_id: user.id,
      host_username: user.username,
      live?: false,
      status: :ready,
      playing?: true,
      position_ms: start_ms,
      updated_at: nil,
      error: nil
    }

    case DiscordAudio.play_from(item.media_path, start_ms, user) do
      :ok -> :ok
      {:error, reason} -> Logger.info("Discord video audio skipped: #{reason}")
    end

    session = %{session | updated_at: now_ms()}
    state = %{state | session: session} |> reschedule_end_timer()
    track_video_play(session)
    publish_now_playing(session)
    broadcast_state(session)
    broadcast_sync(session)
    state
  end

  defp start_live_from_prefetch(state, item, user) do
    AudioPlayer.clear_playback()
    parent = self()

    session = %Session{
      id: item.id,
      url: item.url,
      youtube_id: item.youtube_id,
      title: item.title,
      thumbnail_url: Map.get(item, :thumbnail_url),
      stream_url: item.stream_url,
      duration_ms: item.duration_ms,
      host_user_id: user.id,
      host_username: user.username,
      live?: true,
      status: :remuxing,
      playing?: false,
      position_ms: Extractor.start_offset_ms(item.url),
      updated_at: now_ms()
    }

    broadcast_state(session)

    task =
      Task.Supervisor.async_nolink(Soundboard.AudioTaskSupervisor, fn ->
        case LiveHls.start(item.stream_url, item.id, waiter: self(), notify: parent) do
          {:ok, remux} ->
            extraction = %{
              youtube_id: item.youtube_id,
              title: item.title,
              thumbnail_url: Map.get(item, :thumbnail_url),
              media_path: nil,
              stream_url: item.stream_url,
              duration_ms: item.duration_ms,
              live?: true,
              url: item.url
            }

            {:ok, extraction, remux}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    %{state | session: session, task_ref: task.ref, task_pid: task.pid}
  end

  defp adopt_in_flight_prefetch(state, item, user) do
    AudioPlayer.clear_playback()

    status =
      case item.prefetch_status do
        :remuxing -> :remuxing
        _ -> :fetching
      end

    session = %Session{
      id: item.id,
      url: item.url,
      youtube_id: item.youtube_id,
      title: item.title,
      thumbnail_url: Map.get(item, :thumbnail_url),
      media_path: item.media_path,
      stream_url: item.stream_url,
      duration_ms: item.duration_ms,
      host_user_id: user.id,
      host_username: user.username,
      live?: item.live? == true,
      status: status,
      playing?: false,
      position_ms: Extractor.start_offset_ms(item.url),
      updated_at: now_ms()
    }

    broadcast_state(session)

    %{state | session: session, task_ref: item.prefetch_ref, task_pid: item.prefetch_pid}
  end

  defp ingest(url, session_id, parent) do
    SessionsPath.ensure_session_dir(session_id)

    case Extractor.download(url, SessionsPath.session_dir(session_id)) do
      {:ok, %{live?: true, stream_url: stream_url} = extraction} when is_binary(stream_url) ->
        send(parent, {:video_ingest_status, session_id, :remuxing})

        case LiveHls.start(stream_url, session_id, waiter: self(), notify: parent) do
          {:ok, remux} -> {:ok, extraction, remux}
          {:error, reason} -> {:error, reason}
        end

      {:ok, extraction} ->
        send(parent, {:video_ingest_status, session_id, :remuxing})

        case HlsRemux.remux(extraction.media_path, session_id) do
          {:ok, remux} -> {:ok, extraction, remux}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_prefetch(%QueueItem{} = item) do
    parent = self()

    task =
      Task.Supervisor.async_nolink(Soundboard.AudioTaskSupervisor, fn ->
        prefetch_ingest(item.url, item.id, parent)
      end)

    item = %{
      item
      | prefetch_ref: task.ref,
        prefetch_pid: task.pid,
        progress_percent: max(item.progress_percent || 0, 10),
        prefetch_status: :fetching
    }

    {item, task}
  end

  defp maybe_start_next_prefetch(%{session: %Session{status: status}} = state)
       when status in [:fetching, :remuxing],
       do: state

  defp maybe_start_next_prefetch(state) do
    if active_prefetch?(state.queue) do
      state
    else
      state |> latest_pending_prefetch() |> start_pending_prefetch(state)
    end
  end

  defp active_prefetch?(queue) do
    Enum.any?(queue, fn item ->
      item.prefetch_status in [:fetching, :remuxing] and
        is_reference(item.prefetch_ref) and is_pid(item.prefetch_pid)
    end)
  end

  defp latest_pending_prefetch(state) do
    Enum.find(Enum.reverse(state.queue), &(&1.prefetch_status == :pending))
  end

  defp start_pending_prefetch(nil, state), do: state

  defp start_pending_prefetch(item, state) do
    {item, _task} = start_prefetch(item)
    queue = update_queue_item(state.queue, item.id, fn _ -> item end)
    broadcast_queue(queue)
    %{state | queue: queue}
  end

  defp prefetch_ingest(url, session_id, parent) do
    SessionsPath.ensure_session_dir(session_id)

    with {:ok, meta} <- Extractor.probe(url) do
      send(parent, {:video_prefetch_meta, session_id, meta})
      prefetch_after_probe(meta, url, session_id, parent)
    end
  end

  defp prefetch_after_probe(%{live_status: :is_upcoming}, _url, _session_id, _parent) do
    {:error, "That live stream hasn't started yet."}
  end

  defp prefetch_after_probe(_meta, url, session_id, parent) do
    url
    |> Extractor.download(SessionsPath.session_dir(session_id))
    |> handle_prefetch_download(session_id, parent)
  end

  defp handle_prefetch_download({:ok, %{live?: true} = extraction}, session_id, parent) do
    send(parent, {:video_prefetch_meta, session_id, extraction})
    {:ok, :live, extraction}
  end

  defp handle_prefetch_download({:ok, extraction}, session_id, parent) do
    send(parent, {:video_prefetch_meta, session_id, extraction})
    send(parent, {:video_prefetch_status, session_id, :remuxing})
    remux_prefetch(extraction, session_id)
  end

  defp handle_prefetch_download({:error, reason}, _session_id, _parent), do: {:error, reason}

  defp remux_prefetch(extraction, session_id) do
    case HlsRemux.remux(extraction.media_path, session_id) do
      {:ok, remux} -> {:ok, :vod, extraction, remux}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_prefetch_result(state, item, {:ok, :vod, extraction, remux}) do
    queue =
      update_queue_item(state.queue, item.id, fn item ->
        %{
          item
          | title: extraction.title,
            thumbnail_url: Map.get(extraction, :thumbnail_url),
            youtube_id: extraction.youtube_id,
            duration_ms: extraction.duration_ms,
            media_path: extraction.media_path,
            remux_mode: remux.mode,
            live?: false,
            prefetch_status: :ready,
            prefetch_ref: nil,
            prefetch_pid: nil,
            progress_percent: 100,
            error: nil
        }
      end)

    broadcast_queue(queue)
    %{state | queue: queue}
  end

  defp handle_prefetch_result(state, item, {:ok, :live, extraction}) do
    queue =
      update_queue_item(state.queue, item.id, fn item ->
        %{
          item
          | title: extraction.title,
            thumbnail_url: Map.get(extraction, :thumbnail_url),
            youtube_id: extraction.youtube_id,
            duration_ms: extraction.duration_ms,
            stream_url: extraction.stream_url,
            live?: true,
            prefetch_status: :ready,
            prefetch_ref: nil,
            prefetch_pid: nil,
            progress_percent: 100,
            error: nil
        }
      end)

    broadcast_queue(queue)
    %{state | queue: queue}
  end

  defp handle_prefetch_result(state, item, {:error, reason}) do
    queue =
      update_queue_item(state.queue, item.id, fn item ->
        %{
          item
          | prefetch_status: :error,
            error: reason,
            prefetch_ref: nil,
            prefetch_pid: nil
        }
      end)

    broadcast_queue(queue)
    %{state | queue: queue}
  end

  defp handle_prefetch_result(state, item, other) do
    handle_prefetch_result(state, item, {:error, "Unexpected prefetch result: #{inspect(other)}"})
  end

  defp normalize_ingest_result({:ok, :vod, extraction, remux}), do: {:ok, extraction, remux}
  defp normalize_ingest_result({:ok, extraction, remux}), do: {:ok, extraction, remux}
  defp normalize_ingest_result({:error, reason}), do: {:error, reason}
  defp normalize_ingest_result(other), do: {:error, "Unexpected ingest result: #{inspect(other)}"}

  defp handle_playback_result(state, session, {:ok, extraction, remux}) do
    live? = extraction.live? == true
    holder = Map.get(remux, :holder_pid)

    if live? and (not is_pid(holder) or not Process.alive?(holder)) do
      handle_dead_live_remux(state, session)
    else
      activate_ingested_session(state, session, extraction, remux, holder, live?)
    end
  end

  defp handle_playback_result(state, session, {:error, reason}) do
    session = %{
      session
      | status: :error,
        error: reason,
        playing?: false,
        updated_at: now_ms()
    }

    broadcast_state(session)
    PubSubTopics.broadcast_video_error(reason)
    advance_queue_after_error(%{state | session: session})
  end

  defp handle_dead_live_remux(state, session) do
    session = %{
      session
      | status: :error,
        error: "Live stream remux exited before playback could start",
        playing?: false,
        updated_at: now_ms()
    }

    broadcast_state(session)
    PubSubTopics.broadcast_video_error(session.error)
    advance_queue_after_error(%{state | session: session})
  end

  defp activate_ingested_session(state, session, extraction, remux, holder, live?) do
    start_ms = initial_position_ms(session, extraction, live?)
    live_monitor = if is_pid(holder), do: Process.monitor(holder), else: nil

    session = ready_session(session, extraction, remux, holder, live?, start_ms)
    start_discord_audio(session, live?, start_ms)
    session = %{session | updated_at: now_ms()}

    state =
      %{state | session: session, live_monitor_ref: live_monitor}
      |> reschedule_end_timer()

    track_video_play(session)
    publish_now_playing(session)
    broadcast_state(session)
    broadcast_sync(session)
    state
  end

  defp ready_session(session, extraction, remux, holder, live?, start_ms) do
    %{
      session
      | youtube_id: extraction.youtube_id,
        title: extraction.title,
        thumbnail_url: Map.get(extraction, :thumbnail_url),
        media_path: extraction.media_path,
        stream_url: extraction.stream_url,
        duration_ms: extraction.duration_ms,
        hls_url: "/video/sessions/#{session.id}/index.m3u8",
        remux_mode: remux.mode,
        live_pid: holder,
        live?: live?,
        status: :ready,
        playing?: true,
        position_ms: start_ms,
        updated_at: nil,
        error: nil
    }
  end

  defp start_discord_audio(session, live?, start_ms) do
    # Live Discord uses the upstream stream URL; VOD uses downloaded media.
    case DiscordAudio.play_from(
           discord_source(session),
           if(live?, do: 0, else: start_ms),
           playback_actor(session)
         ) do
      :ok -> :ok
      {:error, reason} -> Logger.info("Discord video audio skipped: #{reason}")
    end
  end

  defp find_prefetch_item(queue, ref) do
    Enum.find(queue, fn
      %QueueItem{prefetch_ref: ^ref} -> true
      _ -> false
    end)
  end

  defp update_queue_item(queue, item_id, fun) do
    Enum.map(queue, fn
      %QueueItem{id: ^item_id} = item -> fun.(item)
      item -> item
    end)
  end

  defp cancel_prefetch_task(%QueueItem{prefetch_ref: ref, prefetch_pid: pid}) do
    if is_reference(ref), do: Process.demonitor(ref, [:flush])

    if is_pid(pid) and Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    :ok
  end

  defp cancel_and_cleanup_prefetch(%QueueItem{} = item) do
    cancel_prefetch_task(item)
    SessionsPath.cleanup_session(item.id)
    :ok
  end

  defp require_host(nil, _user), do: {:error, "No video is playing"}

  defp require_host(%Session{host_user_id: host_id} = session, %User{id: id}) do
    if host_id == id, do: {:ok, session}, else: {:error, "Only the host can control playback"}
  end

  defp require_queue_control(%{session: %Session{host_user_id: host_id}}, %User{id: id})
       when host_id == id,
       do: {:ok, :host}

  defp require_queue_control(
         %{session: nil, queue: [%QueueItem{queued_by_user_id: uid} | _]},
         %User{
           id: id
         }
       )
       when uid == id,
       do: {:ok, :queued_by}

  defp require_queue_control(%{session: nil, queue: []}, _), do: {:ok, :empty}

  defp require_queue_control(_, _), do: {:error, "Only the host can manage the queue"}

  defp require_ready(%Session{status: :ready} = session), do: {:ok, session}
  defp require_ready(_), do: {:error, "Video is not ready yet"}

  defp maybe_restart_discord(%Session{} = session) do
    case discord_source(session) do
      path when is_binary(path) ->
        start_ms = if session.live?, do: 0, else: session.position_ms || 0
        DiscordAudio.play_from(path, start_ms, playback_actor(session))

      _ ->
        :ok
    end
  end

  defp playback_actor(%Session{host_user_id: id}) when is_integer(id) do
    case Accounts.get_user(id) do
      %User{} = user -> user
      _ -> nil
    end
  end

  defp playback_actor(%Session{host_username: name}) when is_binary(name), do: name
  defp playback_actor(_), do: nil

  defp discord_source(%Session{live?: true, stream_url: url}) when is_binary(url), do: url

  defp discord_source(%Session{media_path: path}) when is_binary(path), do: path
  defp discord_source(_), do: nil

  defp estimated_position_ms(%Session{live?: true, playing?: true}), do: nil

  defp estimated_position_ms(%Session{playing?: false, position_ms: pos}), do: pos || 0

  defp estimated_position_ms(%Session{
         playing?: true,
         position_ms: pos,
         updated_at: updated_at,
         duration_ms: duration_ms
       })
       when is_integer(updated_at) do
    elapsed = now_ms() - updated_at
    clamp_position((pos || 0) + elapsed, duration_ms)
  end

  defp estimated_position_ms(_), do: 0

  defp clamp_position(pos, nil), do: max(pos, 0)
  defp clamp_position(pos, duration) when is_integer(duration), do: pos |> max(0) |> min(duration)

  defp broadcast_state(session) do
    PubSubTopics.broadcast_video_state(public_session(session))
  end

  defp broadcast_sync(session) do
    PubSubTopics.broadcast_video_sync(%{
      id: session.id,
      position_ms: estimated_position_ms(session),
      playing?: session.playing?,
      live?: session.live? == true,
      updated_at: session.updated_at || now_ms()
    })
  end

  defp broadcast_queue(queue) do
    PubSubTopics.broadcast_video_queue(Enum.map(queue, &public_queue_item/1))
  end

  defp publish_now_playing(%Session{playing?: true} = session) do
    title =
      cond do
        is_binary(session.title) and String.trim(session.title) != "" -> session.title
        is_binary(session.youtube_id) -> "YouTube #{session.youtube_id}"
        true -> "YouTube video"
      end

    played_by =
      if is_binary(session.host_username) and session.host_username != "",
        do: session.host_username,
        else: "Someone"

    {duration_ms, started_at} = now_playing_timing(session)

    Notifier.sound_played(title, played_by, %{
      duration_ms: duration_ms,
      started_at: started_at,
      live?: session.live? == true,
      media_type: "youtube",
      thumbnail_url:
        Map.get(session, :thumbnail_url) || Extractor.thumbnail_url(session.youtube_id),
      navigate_to: "/video"
    })

    :ok
  end

  defp publish_now_playing(_), do: :ok

  defp track_video_play(%Session{} = session) do
    attrs = %{youtube_id: session.youtube_id, title: session.title, url: session.url}

    case Stats.track_youtube_play(attrs, session.host_user_id) do
      {:ok, _play} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Could not track YouTube play: #{inspect(changeset.errors)}")
    end
  end

  defp now_playing_timing(%Session{live?: true}) do
    {nil, System.system_time(:millisecond)}
  end

  defp now_playing_timing(%Session{duration_ms: duration_ms, position_ms: position_ms})
       when is_integer(duration_ms) and duration_ms > 0 do
    position = position_ms || 0
    started_at = System.system_time(:millisecond) - max(position, 0)
    {duration_ms, started_at}
  end

  defp now_playing_timing(_), do: {nil, System.system_time(:millisecond)}

  defp clear_now_playing do
    Notifier.playback_stopped()
  end

  defp cleanup_session(nil), do: :ok

  defp cleanup_session(%Session{} = session) do
    LiveHls.stop(session.live_pid)

    if is_binary(session.id) do
      SessionsPath.cleanup_session(session.id)
    end

    :ok
  end

  defp demonitor_live(%{live_monitor_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    %{state | live_monitor_ref: nil}
  end

  defp demonitor_live(state), do: state

  defp cancel_task(%{task_ref: ref, task_pid: pid} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    if is_pid(pid) and Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    %{state | task_ref: nil, task_pid: nil}
  end

  defp cancel_task(state), do: state

  defp cancel_end_timer(%{end_timer_ref: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | end_timer_ref: nil}
  end

  defp cancel_end_timer(state), do: state

  defp reschedule_end_timer(state) do
    state = cancel_end_timer(state)

    case state.session do
      %Session{live?: true} ->
        # Live streams end when the remux process exits.
        state

      %Session{status: :ready, playing?: true, id: id, duration_ms: duration}
      when is_integer(duration) and duration > 0 ->
        remaining = max(duration - estimated_position_ms(state.session), 0) + 500
        ref = Process.send_after(self(), {:video_ended, id}, remaining)
        %{state | end_timer_ref: ref}

      _ ->
        state
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp now_ms, do: System.system_time(:millisecond)
end
