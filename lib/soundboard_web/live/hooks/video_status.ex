defmodule SoundboardWeb.Live.Hooks.VideoStatus do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Soundboard.{PubSubTopics, VideoPlayer}
  alias SoundboardWeb.VideoLive

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      PubSubTopics.subscribe_video()
    end

    socket =
      socket
      |> assign(:video_live, VideoPlayer.live?())
      |> attach_hook(:video_status_messages, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  defp handle_info({:video_state, session}, socket) do
    live? =
      is_map(session) and (session[:status] || session.status) in [:fetching, :remuxing, :ready]

    socket = assign(socket, :video_live, live?)
    continue_or_halt(socket)
  end

  defp handle_info({:video_stopped}, socket) do
    socket = assign(socket, :video_live, false)
    continue_or_halt(socket)
  end

  defp handle_info(msg, socket)
       when elem(msg, 0) in [:video_sync, :video_queue, :video_error] do
    continue_or_halt(socket)
  end

  defp handle_info(_msg, socket), do: {:cont, socket}

  # VideoLive implements its own video handlers; other LiveViews should not.
  defp continue_or_halt(%{view: VideoLive} = socket), do: {:cont, socket}
  defp continue_or_halt(socket), do: {:halt, socket}
end
