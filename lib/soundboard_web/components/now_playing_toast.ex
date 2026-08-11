defmodule SoundboardWeb.Components.NowPlayingToast do
  @moduledoc false
  use SoundboardWeb, :html

  attr :now_playing, :map, default: nil
  attr :favorites, :list, default: []
  attr :current_user, :any, default: nil
  attr :theme, :string, default: "classic"

  def now_playing_toast(assigns) do
    live? = assigns.now_playing && Map.get(assigns.now_playing, :live?, false) == true
    assigns = assign(assigns, :live?, live?)

    ~H"""
    <div
      :if={@now_playing}
      id="now-playing-toast"
      role="status"
      aria-live="polite"
      data-theme-toast={@theme}
      class={toast_shell_classes(@theme)}
      phx-hook={if @live?, do: nil, else: "PlaybackProgress"}
      data-duration-ms={@now_playing.duration_ms || ""}
      data-started-at={@now_playing.started_at}
    >
      <div class="flex items-start gap-3">
        <div class="min-w-0 flex-1">
          <p class={toast_label_classes(@theme)}>
            {if @live?, do: "Live Now", else: "Now Playing"}
          </p>
          <p class={toast_title_classes(@theme)} title={@now_playing.display_name}>
            {@now_playing.display_name}
          </p>
          <p class={toast_meta_classes(@theme)}>
            by {@now_playing.played_by}
          </p>
        </div>

        <div class="flex items-center gap-1 shrink-0">
          <button
            :if={@current_user && @now_playing.sound_id}
            type="button"
            phx-click="toggle_favorite"
            phx-value-sound-id={@now_playing.sound_id}
            class={toast_icon_btn_classes(@theme)}
            aria-label={
              if @now_playing.sound_id in @favorites,
                do: "Remove from favorites",
                else: "Add to favorites"
            }
          >
            <%= if @now_playing.sound_id in @favorites do %>
              <.icon
                name="hero-heart-solid"
                class={"w-5 h-5 #{toast_fav_active_classes(@theme)}"}
              />
            <% else %>
              <.icon name="hero-heart" class="w-5 h-5" />
            <% end %>
          </button>

          <button
            type="button"
            phx-click="dismiss_now_playing"
            class={toast_icon_btn_classes(@theme)}
            aria-label="Dismiss now playing"
          >
            <.icon name="hero-x-mark-solid" class="w-5 h-5 opacity-60" />
          </button>
        </div>
      </div>

      <div :if={!@live?} class={toast_track_classes(@theme)}>
        <div
          data-role="progress-bar"
          class={[
            toast_fill_classes(@theme),
            is_nil(@now_playing.duration_ms) && "w-1/3 animate-pulse"
          ]}
          style={if @now_playing.duration_ms, do: "width: 0%", else: nil}
        >
        </div>
      </div>
    </div>
    """
  end

  defp toast_shell_classes("desk") do
    "desk-toast desk-toast-info p-3"
  end

  defp toast_shell_classes(_) do
    "rounded-lg p-3 ring-1 bg-gray-900 text-gray-100 ring-blue-500/60 shadow-md"
  end

  defp toast_label_classes("desk") do
    "text-[10px] font-semibold uppercase tracking-[0.16em] text-[var(--signal)]"
  end

  defp toast_label_classes(_) do
    "text-xs font-semibold uppercase tracking-wide text-blue-300"
  end

  defp toast_title_classes("desk") do
    "mt-1 text-sm font-bold uppercase tracking-[0.03em] truncate text-[var(--ink)]"
  end

  defp toast_title_classes(_) do
    "mt-1 text-sm font-semibold truncate"
  end

  defp toast_meta_classes("desk") do
    "text-[10px] uppercase tracking-[0.1em] truncate text-[var(--mute)]"
  end

  defp toast_meta_classes(_) do
    "text-xs text-gray-400 truncate"
  end

  defp toast_icon_btn_classes("desk") do
    "flex items-center justify-center w-8 h-8 rounded-[3px] text-[var(--mute)] hover:text-[var(--ink)] transition-colors"
  end

  defp toast_icon_btn_classes(_) do
    "flex items-center justify-center w-8 h-8 rounded-md text-gray-500 hover:text-red-400 transition-colors"
  end

  defp toast_fav_active_classes("desk"), do: "text-[var(--signal)]"
  defp toast_fav_active_classes(_), do: "text-red-500"

  defp toast_track_classes("desk") do
    "mt-3 h-1.5 w-full overflow-hidden rounded-[2px] bg-[rgba(19,20,22,0.16)]"
  end

  defp toast_track_classes(_) do
    "mt-3 h-1.5 w-full overflow-hidden rounded-full bg-gray-700"
  end

  defp toast_fill_classes("desk") do
    "h-full rounded-[2px] bg-[var(--signal)] transition-[width] duration-100 ease-linear"
  end

  defp toast_fill_classes(_) do
    "h-full rounded-full bg-blue-400 transition-[width] duration-100 ease-linear"
  end
end
