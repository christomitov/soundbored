defmodule SoundboardWeb.Components.Layouts.Navbar do
  @moduledoc """
  The navbar component.
  """
  use Phoenix.LiveComponent
  use SoundboardWeb, :html

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
    <nav class="fixed w-full top-0 left-0 right-0 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 z-50">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <div class="flex">
            <div class="flex-shrink-0 flex items-center">
              <span class="text-xl font-bold text-gray-800 dark:text-white">
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
              <.nav_link navigate="/stats" active={current_page?(@current_path, "/leaderboard")}>
                Stats
              </.nav_link>
            </div>
          </div>

          <div class="hidden sm:ml-6 sm:flex sm:items-center">
            <div class="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
              <%= @presences
                  |> Enum.flat_map(fn {_id, presence} ->
                    presence.metas
                    |> Enum.map(& &1.user)
                  end)
                  |> Enum.uniq_by(& &1.username)
                  |> Enum.map(fn user -> %>
                <div class="flex items-center gap-1">
                  <span
                    id={"user-#{user.username}"}
                    data-username={user.username}
                    class={[
                      "px-2 py-1 rounded-full text-xs select-none transition-all duration-150 flex items-center gap-1",
                      "cursor-default",
                      SoundboardWeb.Live.PresenceHandler.get_user_color(user.username)
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
              class="inline-flex items-center justify-center p-2 rounded-md text-gray-400 hover:text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500"
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
          <.mobile_nav_link navigate="/stats" active={current_page?(@current_path, "/leaderboard")}>
            Stats
          </.mobile_nav_link>
        </div>
        <div class="pt-4 pb-3 border-t border-gray-200 dark:border-gray-700">
          <div class="space-y-2 px-4">
            <%= @presences
                |> Enum.flat_map(fn {_id, presence} ->
                  presence.metas
                  |> Enum.map(& &1.user)
                end)
                |> Enum.uniq_by(& &1.username)
                |> Enum.map(fn user -> %>
              <div class="flex items-center gap-2 py-2">
                <span
                  id={"mobile-user-#{user.username}"}
                  data-username={user.username}
                  class={[
                    "px-3 py-2 rounded-full text-sm select-none transition-all duration-150 flex items-center gap-2",
                    "cursor-default leading-relaxed tracking-wide",
                    SoundboardWeb.Live.PresenceHandler.get_user_color(user.username)
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
        "inline-flex items-center px-1 pt-1 text-sm font-medium",
        if(@active,
          do: "border-b-2 border-blue-500 text-gray-900 dark:text-gray-100",
          else:
            "border-b-2 border-transparent text-gray-500 dark:text-gray-400 hover:border-gray-300 dark:hover:border-gray-600 hover:text-gray-700 dark:hover:text-gray-200"
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
          do: "bg-blue-50 dark:bg-blue-900/50 border-blue-500 text-blue-700 dark:text-blue-100",
          else:
            "border-transparent text-gray-600 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 hover:border-gray-300 dark:hover:border-gray-600 hover:text-gray-800 dark:hover:text-gray-200"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp current_page?(current_path, path), do: current_path == path
end
