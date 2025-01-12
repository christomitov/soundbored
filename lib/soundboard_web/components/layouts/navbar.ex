defmodule SoundboardWeb.Components.Layouts.Navbar do
  use Phoenix.LiveComponent
  use SoundboardWeb, :html

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

  defp current_page?(current_path, path), do: current_path == path
end
