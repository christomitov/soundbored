defmodule SoundboardWeb.Components.Layouts.Navbar do
  use Phoenix.LiveComponent
  alias Phoenix.LiveView.JS
  require Logger

  @presence_topic "soundboard:presence"

  @impl true
  def mount(socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, @presence_topic)
    end

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, @presence_topic)
    end

    Logger.debug(
      "Navbar component updating with assigns: #{inspect(Map.drop(assigns, [:__changed__]))}"
    )

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <nav
      id={@id}
      class="fixed w-full top-0 left-0 right-0 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 z-50"
    >
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
                    |> Enum.map(& &1.user.username)
                  end)
                  |> Enum.uniq()
                  |> Enum.map(fn username -> %>
                <span
                  id={"user-#{username}"}
                  data-username={username}
                  class={[
                    "px-2 py-1 rounded-full text-xs select-none transition-all duration-150",
                    if(@current_user && username == @current_user.username,
                      do: "cursor-pointer transform hover:scale-105 active:scale-95",
                      else: "cursor-default"
                    ),
                    SoundboardWeb.Live.PresenceHandler.get_user_color(username)
                  ]}
                  phx-click={
                    if @current_user && username == @current_user.username, do: "cycle_user_color"
                  }
                  phx-value-username={username}
                  phx-hook={
                    if @current_user && username == @current_user.username, do: "ClickFeedback"
                  }
                >
                  {username}
                </span>
              <% end) %>
            </div>
          </div>

          <div class="-mr-2 flex items-center sm:hidden">
            <button
              type="button"
              class="inline-flex items-center justify-center p-2 rounded-md text-gray-400 hover:text-gray-500 hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-inset focus:ring-blue-500 dark:hover:bg-gray-700 dark:hover:text-gray-300"
              aria-controls="mobile-menu"
              aria-expanded="false"
              phx-click={
                JS.toggle(to: "#mobile-menu")
                |> JS.toggle(
                  to: "#mobile-menu div.menu-content",
                  in: "translate-x-0",
                  out: "translate-x-full"
                )
              }
            >
              <svg
                class="h-6 w-6"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"
                />
              </svg>
            </button>
          </div>
        </div>
      </div>

      <div class="sm:hidden" id="mobile-menu" style="display: none;">
        <div
          class="fixed inset-0 bg-gray-600 bg-opacity-75 transition-opacity z-40"
          phx-click={
            JS.toggle(to: "#mobile-menu")
            |> JS.toggle(
              to: "#mobile-menu div.menu-content",
              in: "translate-x-0",
              out: "translate-x-full"
            )
          }
        >
        </div>
        <div class="menu-content fixed inset-y-0 right-0 w-64 bg-white dark:bg-gray-800 shadow-lg transform translate-x-full transition-transform duration-300 ease-in-out z-50">
          <div class="pt-2 pb-3 space-y-1">
            <.mobile_nav_link navigate="/" active={current_page?(@current_path, "/")}>
              Sounds
            </.mobile_nav_link>
            <.mobile_nav_link
              navigate="/favorites"
              active={current_page?(@current_path, "/favorites")}
            >
              Favorites
            </.mobile_nav_link>
            <.mobile_nav_link
              navigate="/leaderboard"
              active={current_page?(@current_path, "/leaderboard")}
            >
              Leaderboard
            </.mobile_nav_link>
          </div>
          <div class="pt-4 pb-3 border-t border-gray-200 dark:border-gray-700">
            <div class="flex flex-wrap items-center gap-2 px-4 text-sm text-gray-600 dark:text-gray-400">
              <%= @presences
                  |> Enum.flat_map(fn {_id, presence} ->
                    presence.metas
                    |> Enum.map(& &1.user.username)
                  end)
                  |> Enum.uniq()
                  |> Enum.map(fn username -> %>
                <span class={"px-2 py-1 rounded-full text-xs #{SoundboardWeb.Live.PresenceHandler.get_user_color(username)}"}>
                  {username}
                </span>
              <% end) %>
            </div>
          </div>
        </div>
      </div>
    </nav>
    """
  end

  def nav_link(assigns) do
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

  def mobile_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "block pl-3 pr-4 py-2 text-base font-medium border-l-4",
        @active &&
          "bg-blue-50 border-blue-500 text-blue-700 dark:bg-blue-900/50 dark:border-blue-400 dark:text-blue-100",
        !@active &&
          "border-transparent text-gray-500 hover:bg-gray-50 hover:border-gray-300 hover:text-gray-700 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-white dark:hover:border-gray-600"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp current_page?(current_path, path), do: current_path == path
end
