defmodule SoundboardWeb.Components.Layouts.Transport do
  @moduledoc """
  Fixed bottom transport bar used by the desk theme.
  """
  use SoundboardWeb, :html

  attr :now_playing, :map, default: nil
  attr :favorites, :list, default: []
  attr :current_user, :any, default: nil

  def transport(assigns) do
    playing? = not is_nil(assigns.now_playing)
    video? = video_now_playing?(assigns.now_playing)

    assigns =
      assigns
      |> assign(:playing?, playing?)
      |> assign(:video?, video?)
      |> assign(:fav?, favorite?(assigns.now_playing, assigns.favorites))

    ~H"""
    <footer class={["transport", @playing? && "playing"]} id="desk-transport">
      <.link
        :if={@video? && @now_playing.thumbnail_url}
        navigate={@now_playing.navigate_to}
        class="transport-art"
        aria-label="Open video player"
      >
        <img src={@now_playing.thumbnail_url} alt="" />
      </.link>

      <div class={["tnow", @now_playing && @now_playing[:live?] && "tnow-live"]}>
        <%= if @now_playing do %>
          <.link
            :if={@video?}
            navigate={@now_playing.navigate_to}
            class="tnow-link"
            title={@now_playing.display_name}
          >
            <b>{@now_playing.display_name}</b>
          </.link>
          <b :if={!@video?} title={@now_playing.display_name}>{@now_playing.display_name}</b>
          <em>by {@now_playing.played_by}</em>
        <% else %>
          <b>No sound loaded</b>
          <em>Hit a pad to play</em>
        <% end %>
      </div>

      <div
        :if={@now_playing && !@now_playing[:live?]}
        class="scrub"
        id="desk-transport-progress"
        phx-hook="PlaybackProgress"
        data-duration-ms={@now_playing.duration_ms || ""}
        data-started-at={@now_playing.started_at}
      >
        <div class="scrub-track">
          <div
            data-role="progress-bar"
            class={[
              "scrub-fill",
              is_nil(@now_playing.duration_ms) && "animate-pulse"
            ]}
            style={if @now_playing.duration_ms, do: "width: 0%", else: "width: 33%"}
          >
          </div>
        </div>
      </div>

      <div class="vu" aria-hidden="true">
        <i></i><i></i><i></i><i></i><i></i>
      </div>

      <button
        :if={@current_user && @now_playing && @now_playing.sound_id}
        type="button"
        phx-click="toggle_favorite"
        phx-value-sound-id={@now_playing.sound_id}
        class="tbtn icon"
        aria-pressed={to_string(@fav?)}
        aria-label={if @fav?, do: "Remove from favorites", else: "Add to favorites"}
      >
        {if @fav?, do: "★", else: "☆"}
      </button>

      <button type="button" phx-click="stop_sound" class="tbtn stop">Stop all</button>
    </footer>
    """
  end

  defp favorite?(nil, _), do: false
  defp favorite?(%{sound_id: id}, favorites) when is_integer(id), do: id in favorites
  defp favorite?(_, _), do: false

  defp video_now_playing?(%{media_type: "youtube", navigate_to: path})
       when is_binary(path),
       do: true

  defp video_now_playing?(_), do: false
end
