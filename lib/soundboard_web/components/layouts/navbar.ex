defmodule SoundboardWeb.Components.Layouts.Navbar do
  @moduledoc """
  The navbar component.
  """
  use SoundboardWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :show_mobile_menu, false)}
  end

  @impl true
  def handle_event("toggle-mobile-menu", _, socket) do
    {:noreply, assign(socket, :show_mobile_menu, !socket.assigns.show_mobile_menu)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <nav class="fixed inset-x-0 top-0 z-50 w-full border-b border-line bg-surface text-ink shadow-sm retro:shadow-theme">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <div class="flex">
            <div class="flex-shrink-0 flex items-center">
              <span class="font-display text-xl font-bold text-ink desk:uppercase desk:tracking-[0.16em] retro:italic">
                <.link navigate="/">SoundBored</.link>
              </span>
            </div>
            <div class="hidden sm:ml-6 sm:flex sm:space-x-8">
              <.nav_link navigate="/" active={current_page?(@current_path, "/")}>
                Sounds
              </.nav_link>
              <.nav_link navigate="/favorites" active={current_page?(@current_path, "/favorites")}>
                Favorites
              </.nav_link>
              <.nav_link navigate="/stats" active={current_page?(@current_path, "/stats")}>
                Stats
              </.nav_link>
              <%= if @current_user do %>
                <.nav_link
                  navigate="/settings"
                  active={current_page?(@current_path, "/settings")}
                >
                  Settings
                </.nav_link>
              <% end %>
            </div>
          </div>

          <div class="hidden sm:ml-6 sm:flex sm:items-center">
            <div class="flex items-center gap-2 text-sm text-muted">
              <%= visible_users(@presences)
                  |> Enum.map(fn user -> %>
                <div class="flex items-center gap-1">
                  <span
                    id={"user-#{user.username}"}
                    data-username={user.username}
                    class={[
                      "px-2 py-1 rounded-full text-xs select-none transition-all duration-150 flex items-center gap-1",
                      "cursor-default",
                      SoundboardWeb.PresenceHandler.get_user_color(user.username)
                    ]}
                  >
                    <img
                      src={user.avatar}
                      class="w-4 h-4 rounded-full"
                      alt={"#{user.username}'s avatar"}
                    />
                    {user.username}
                  </span>
                </div>
              <% end) %>
            </div>
          </div>

          <div class="-mr-2 flex items-center sm:hidden">
            <button
              type="button"
              class="inline-flex items-center justify-center rounded-theme p-2 text-muted hover:bg-surface-raised hover:text-ink focus:outline-none focus:ring-2 focus:ring-inset focus:ring-accent"
              aria-controls="mobile-menu"
              aria-expanded="false"
              phx-click="toggle-mobile-menu"
              phx-target={@myself}
            >
              <span class="sr-only">Open main menu</span>
              <!-- Menu open: "hidden", Menu closed: "block" -->
              <svg
                class={["h-6 w-6", (!@show_mobile_menu && "block") || "hidden"]}
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 12h16M4 18h16"
                />
              </svg>
              <!-- Menu open: "block", Menu closed: "hidden" -->
              <svg
                class={["h-6 w-6", (@show_mobile_menu && "block") || "hidden"]}
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>
        </div>
      </div>
      
    <!-- Mobile menu -->
      <div class={["sm:hidden", (!@show_mobile_menu && "hidden") || "block"]} id="mobile-menu">
        <div class="pt-2 pb-3 space-y-1">
          <.mobile_nav_link navigate="/" active={current_page?(@current_path, "/")}>
            Sounds
          </.mobile_nav_link>
          <.mobile_nav_link navigate="/favorites" active={current_page?(@current_path, "/favorites")}>
            Favorites
          </.mobile_nav_link>
          <.mobile_nav_link navigate="/stats" active={current_page?(@current_path, "/stats")}>
            Stats
          </.mobile_nav_link>
          <%= if @current_user do %>
            <.mobile_nav_link
              navigate="/settings"
              active={current_page?(@current_path, "/settings")}
            >
              Settings
            </.mobile_nav_link>
          <% end %>
        </div>
        <div class="border-t border-line pb-3 pt-4">
          <div class="space-y-2 px-4">
            <%= visible_users(@presences)
                |> Enum.map(fn user -> %>
              <div class="flex items-center gap-2 py-2">
                <span
                  id={"mobile-user-#{user.username}"}
                  data-username={user.username}
                  class={[
                    "px-3 py-2 rounded-full text-sm select-none transition-all duration-150 flex items-center gap-2",
                    "cursor-default leading-relaxed tracking-wide",
                    SoundboardWeb.PresenceHandler.get_user_color(user.username)
                  ]}
                >
                  <img
                    src={user.avatar}
                    class="w-5 h-5 rounded-full"
                    alt={"#{user.username}'s avatar"}
                  />
                  <span class="truncate">{user.username}</span>
                </span>
              </div>
            <% end) %>
          </div>
        </div>
      </div>
    </nav>
    """
  end

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "inline-flex items-center px-1 pt-1 text-sm font-medium desk:uppercase desk:tracking-[0.1em]",
        if(@active,
          do: "border-b-2 border-accent text-ink",
          else: "border-b-2 border-transparent text-muted hover:border-line hover:text-ink"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp mobile_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "block pl-4 pr-4 py-3 border-l-4 text-base font-medium leading-relaxed tracking-wide",
        if(@active,
          do: "border-accent bg-surface-raised text-ink",
          else:
            "border-transparent text-muted hover:border-line hover:bg-surface-muted hover:text-ink"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp visible_users(presences) do
    presences
    |> Enum.flat_map(fn {_id, presence} ->
      Enum.map(presence.metas, & &1.user)
    end)
    |> Enum.uniq_by(& &1.username)
  end

  defp current_page?(current_path, path), do: current_path == path
end
