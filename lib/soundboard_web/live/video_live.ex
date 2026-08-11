defmodule SoundboardWeb.VideoLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive

  alias Soundboard.{PubSubTopics, VideoPlayer}
  alias SoundboardWeb.Live.Support.NowPlayingHelpers

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      PubSubTopics.subscribe_playback()
      PubSubTopics.subscribe_video()
    end

    user = get_user_from_session(session)
    video_session = VideoPlayer.session()
    queue = VideoPlayer.queue()

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/video")
      |> assign(:current_user, user)
      |> assign(:url_input, "")
      |> assign(:video_session, video_session)
      |> assign(:video_queue, queue)
      |> assign(:video_sync, sync_from_session(video_session))
      |> assign(:video_live, video_live?(video_session))
      |> assign(:favorites, [])
      |> NowPlayingHelpers.assign_defaults()
      |> maybe_push_player_state(video_session, sync_from_session(video_session))

    {:ok, socket}
  end

  @impl true
  def handle_event("update_url", %{"url" => url}, socket) do
    {:noreply, assign(socket, :url_input, url)}
  end

  def handle_event("play_video", %{"url" => url}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to play videos")}

      user ->
        case VideoPlayer.play(url, user) do
          {:ok, :playing} ->
            {:noreply, assign(socket, :url_input, "")}

          {:ok, :queued} ->
            {:noreply,
             socket
             |> assign(:url_input, "")
             |> put_flash(:info, "Added to up next")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, reason)}
        end
    end
  end

  def handle_event("stop_video", _params, socket) do
    VideoPlayer.stop()
    {:noreply, socket}
  end

  def handle_event("skip_video", _params, socket) do
    with_host_control(socket, fn user -> VideoPlayer.skip(user) end)
  end

  def handle_event("pause_video", _params, socket) do
    with_host_control(socket, fn user -> VideoPlayer.pause(user) end)
  end

  def handle_event("resume_video", _params, socket) do
    with_host_control(socket, fn user -> VideoPlayer.resume(user) end)
  end

  def handle_event("video_seek", %{"ms" => ms}, socket) do
    position =
      case ms do
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
        _ -> 0
      end

    with_host_control(socket, fn user -> VideoPlayer.seek(user, position) end)
  end

  def handle_event("video_ended", params, socket) do
    session = socket.assigns.video_session
    session_id = Map.get(params, "session_id") || (session && Map.get(session, :id))

    if host?(session, socket.assigns.current_user) and is_binary(session_id) do
      VideoPlayer.notify_media_ended(session_id)
    end

    {:noreply, socket}
  end

  def handle_event("remove_queue_item", %{"id" => id}, socket) do
    with_host_control(socket, fn user -> VideoPlayer.remove_from_queue(user, id) end)
  end

  def handle_event("play_queued_video", %{"id" => id}, socket) do
    with_host_control(socket, fn user -> VideoPlayer.play_queued(user, id) end)
  end

  def handle_event("clear_queue", _params, socket) do
    with_host_control(socket, fn user -> VideoPlayer.clear_queue(user) end)
  end

  def handle_event("request_video_state", _params, socket) do
    session = socket.assigns.video_session
    sync = sync_from_session(session)
    {:noreply, maybe_push_player_state(socket, session, sync)}
  end

  def handle_event("dismiss_now_playing", _params, socket) do
    {:noreply, NowPlayingHelpers.clear(socket)}
  end

  @impl true
  def handle_info({:video_state, session}, socket) do
    sync = sync_from_session(session)

    {:noreply,
     socket
     |> assign(:video_session, session)
     |> assign(:video_sync, sync)
     |> assign(:video_live, video_live?(session))
     |> maybe_push_player_state(session, sync)}
  end

  def handle_info({:video_sync, sync}, socket) do
    payload = %{
      id: Map.get(sync, :id),
      position_ms: Map.get(sync, :position_ms),
      playing: Map.get(sync, :playing?, false),
      live: Map.get(sync, :live?, false),
      updated_at: Map.get(sync, :updated_at)
    }

    {:noreply,
     socket
     |> assign(:video_sync, sync)
     |> push_event("video_sync", payload)}
  end

  def handle_info({:video_queue, queue}, socket) do
    {:noreply, assign(socket, :video_queue, queue || [])}
  end

  def handle_info({:video_stopped}, socket) do
    {:noreply,
     socket
     |> assign(:video_session, nil)
     |> assign(:video_sync, nil)
     |> assign(:video_queue, [])
     |> assign(:video_live, false)
     |> push_event("video_stop", %{})}
  end

  def handle_info({:video_error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  def handle_info({:sound_played, event}, socket) when is_map(event) do
    {:noreply, NowPlayingHelpers.assign_from_event(socket, event)}
  end

  def handle_info({:playback_stopped}, socket) do
    {:noreply, NowPlayingHelpers.clear(socket)}
  end

  def handle_info({:error, _message}, socket), do: {:noreply, socket}

  defp with_host_control(socket, fun) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in")}

      user ->
        case fun.(user) do
          :ok -> {:noreply, socket}
          {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
        end
    end
  end

  defp maybe_push_player_state(socket, session, sync) do
    if connected?(socket) do
      push_event(
        socket,
        "video_state",
        player_payload(session, sync, socket.assigns.current_user)
      )
    else
      socket
    end
  end

  defp player_payload(nil, _sync, _user) do
    %{hls_url: nil, session_id: nil, is_host: false, duration_ms: nil, status: nil}
  end

  defp player_payload(session, sync, user) do
    status = Map.get(session, :status)

    %{
      hls_url: Map.get(session, :hls_url),
      session_id: Map.get(session, :id),
      is_host: host?(session, user),
      duration_ms: Map.get(session, :duration_ms),
      status: status && to_string(status),
      position_ms: sync && Map.get(sync, :position_ms),
      playing: sync && Map.get(sync, :playing?, false),
      live: Map.get(session, :live?, false) || (sync && Map.get(sync, :live?, false)),
      updated_at: sync && Map.get(sync, :updated_at)
    }
  end

  defp sync_from_session(nil), do: nil

  defp sync_from_session(session) do
    %{
      id: Map.get(session, :id),
      position_ms: Map.get(session, :position_ms),
      playing?: Map.get(session, :playing?, false),
      live?: Map.get(session, :live?, false),
      updated_at: Map.get(session, :updated_at)
    }
  end

  defp video_live?(nil), do: false

  defp video_live?(session) do
    Map.get(session, :status) in [:fetching, :remuxing, :ready]
  end

  defp host?(_session, nil), do: false

  defp host?(session, user) when is_map(session) do
    Map.get(session, :host_user_id) == user.id
  end

  defp host?(_, _), do: false

  defp youtube_watch_url(nil), do: nil

  defp youtube_watch_url(session) when is_map(session) do
    cond do
      is_binary(session[:url] || session["url"]) ->
        session[:url] || session["url"]

      id = session[:youtube_id] || session["youtube_id"] ->
        "https://www.youtube.com/watch?v=#{id}"

      true ->
        nil
    end
  end

  defp youtube_watch_url(_), do: nil

  defp prefetch_label(item) when is_map(item) do
    case Map.get(item, :prefetch_status) do
      :ready -> if(Map.get(item, :live?), do: "Ready (live)", else: "Ready")
      :remuxing -> "Preparing stream…"
      :fetching -> "Fetching…"
      :error -> "Failed"
      _ -> "Queued"
    end
  end

  defp prefetch_label(_), do: "Queued"

  defp queue_metadata_loading?(item) when is_map(item) do
    is_nil(Map.get(item, :title)) and
      Map.get(item, :prefetch_status) in [:pending, :fetching, :remuxing]
  end

  defp queue_metadata_loading?(_), do: false

  defp queue_preparing?(item) when is_map(item) do
    Map.get(item, :prefetch_status) in [:pending, :fetching, :remuxing]
  end

  defp queue_preparing?(_), do: false

  defp queue_progress(item) when is_map(item) do
    fallback =
      case Map.get(item, :prefetch_status) do
        :pending -> 5
        :fetching -> if(Map.get(item, :title), do: 30, else: 10)
        :remuxing -> 75
        :ready -> 100
        _ -> 0
      end

    progress =
      case Map.get(item, :progress_percent) do
        value when is_integer(value) -> value
        _ -> fallback
      end

    progress |> max(0) |> min(100)
  end

  defp status_label(nil), do: "Idle"

  defp status_label(session) do
    if Map.get(session, :live?) == true and Map.get(session, :status) == :ready do
      "Live"
    else
      case Map.get(session, :status) do
        :fetching -> "Fetching from YouTube…"
        :remuxing -> "Preparing stream…"
        :ready -> "Playing"
        :error -> "Error"
        _ -> "Idle"
      end
    end
  end

  defp play_button_label(nil), do: "Play"

  defp play_button_label(session) when is_map(session) do
    if Map.get(session, :status) in [:fetching, :remuxing, :ready],
      do: "Add to queue",
      else: "Play"
  end

  defp play_button_label(_), do: "Play"
end
