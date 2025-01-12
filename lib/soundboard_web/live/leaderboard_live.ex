defmodule SoundboardWeb.LeaderboardLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  import Phoenix.Component
  alias Soundboard.{Stats, Favorites, Sound}
  require Logger

  @pubsub_topic "soundboard"
  @presence_topic "soundboard:presence"
  @recent_limit 5

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      :timer.send_interval(60 * 60 * 1000, self(), :check_week_rollover)
      Phoenix.PubSub.subscribe(Soundboard.PubSub, @pubsub_topic)
    end

    current_week = get_week_range()

    {:ok,
     socket
     |> mount_presence(session)
     |> assign(:current_path, "/leaderboard")
     |> assign(:current_user, get_user_from_session(session))
     |> assign(:force_update, 0)
     |> assign(:selected_week, current_week)
     |> assign(:current_week, current_week)
     |> stream_configure(:recent_plays, dom_id: &"play-#{&1.id}")
     |> stream(:recent_plays, [])
     |> assign_stats()}
  end

  @impl true
  def handle_info({:sound_played, %{filename: filename, played_by: username}}, socket) do
    recent_plays = Stats.get_recent_plays(limit: @recent_limit)

    {:noreply,
     socket
     |> stream(:recent_plays, recent_plays, reset: true)
     |> put_flash(:info, "#{username} played #{filename}")
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info({:stats_updated}, socket) do
    {:noreply, assign_stats(socket)}
  end

  @impl true
  def handle_info({:error, message}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: _diff}, socket) do
    presences = Presence.list(@presence_topic)

    {:noreply,
     socket
     |> assign(:presences, presences)
     |> assign(:presence_count, map_size(presences))}
  end

  defp assign_stats(socket) do
    {start_date, end_date} = socket.assigns.selected_week

    # Transform the tuples into maps with an id field
    recent_plays =
      Stats.get_recent_plays(limit: @recent_limit)
      |> Enum.map(fn {filename, username, timestamp} ->
        %{
          id: "#{filename}-#{:erlang.system_time(:millisecond)}",
          filename: filename,
          username: username,
          timestamp: timestamp
        }
      end)

    socket
    |> assign(:top_users, Stats.get_top_users(start_date, end_date, limit: @recent_limit))
    |> assign(:top_sounds, Stats.get_top_sounds(start_date, end_date, limit: @recent_limit))
    |> stream(:recent_plays, recent_plays, reset: true)
    |> assign(:recent_uploads, Sound.get_recent_uploads(limit: @recent_limit))
    |> assign(:favorites, get_favorites(socket.assigns.current_user))
  end

  defp get_favorites(nil), do: []
  defp get_favorites(user), do: Favorites.list_favorites(user.id)

  defp format_timestamp(timestamp) do
    est_time =
      timestamp
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(-5 * 60 * 60, :second)

    Calendar.strftime(est_time, "%b %d, %I:%M %p EST")
  end

  defp get_week_range(date \\ Date.utc_today()) do
    # Get the most recent Monday (beginning of week)
    days_since_monday = Date.day_of_week(date, :monday)
    start_date = Date.add(date, -days_since_monday + 1)
    end_date = Date.add(start_date, 6)
    {start_date, end_date}
  end

  defp format_date_range({start_date, end_date}) do
    "#{Calendar.strftime(start_date, "%b %d")} - #{Calendar.strftime(end_date, "%b %d, %Y")}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="leaderboard" class="max-w-6xl mx-auto px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-bold text-gray-800 dark:text-gray-100">Stats</h1>
        <div class="flex items-center gap-4">
          <button
            phx-click="previous_week"
            class="text-gray-600 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200"
          >
            <.icon name="hero-chevron-left-solid" class="h-5 w-5" />
          </button>
          <div class="text-sm text-gray-600 dark:text-gray-400">
            Week of {format_date_range(@selected_week)}
          </div>
          <button
            phx-click="next_week"
            disabled={@selected_week == @current_week}
            class={[
              "text-gray-600 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200",
              @selected_week == @current_week && "opacity-50 cursor-not-allowed"
            ]}
          >
            <.icon name="hero-chevron-right-solid" class="h-5 w-5" />
          </button>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100 mb-4">Top Users</h2>
          <div class="space-y-2">
            <%= for {username, count} <- @top_users do %>
              <div class="flex justify-between items-center" id={"user-stat-#{username}"}>
                <span class={[
                  "px-2 py-1 rounded-full text-sm flex items-center gap-1",
                  get_user_color_from_presence(username, @presences)
                ]}>
                  <img
                    :if={get_user_avatar_from_presence(username, @presences)}
                    src={get_user_avatar_from_presence(username, @presences)}
                    class="w-4 h-4 rounded-full"
                    alt={"#{username}'s avatar"}
                  />
                  {username}
                </span>
                <span class="text-gray-600 dark:text-gray-400">{count} plays</span>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-200 mb-4">Top Sounds</h2>
          <div class="space-y-3">
            <%= for {sound_name, count} <- @top_sounds do %>
              <div
                class="flex items-center justify-between p-2 rounded-lg bg-gray-50 dark:bg-gray-700 hover:bg-gray-100 dark:hover:bg-gray-600 cursor-pointer group"
                id={"play-top-#{sound_name}"}
                class="px-6"
                phx-click="play_sound"
                phx-value-sound={sound_name}
              >
                <div class="flex items-center gap-3 min-w-0">
                  <div class="min-w-0">
                    <p class="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                      {sound_name}
                    </p>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      {count} plays
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <button
                    phx-click="toggle_favorite"
                    phx-value-sound={sound_name}
                    phx-stop
                    id={"favorite-#{sound_name}"}
                    class="text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-500 mr-2"
                  >
                    <%= if is_favorite?(@favorites, sound_name) do %>
                      <.icon name="hero-heart-solid" class="h-5 w-5 text-red-500" />
                    <% else %>
                      <.icon name="hero-heart" class="h-5 w-5" />
                    <% end %>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <div class="mt-8 grid grid-cols-1 md:grid-cols-2 gap-8">
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-200 mb-4">Recent Plays</h2>
          <div class="space-y-3" id="recent_plays" phx-update="stream">
            <%= for {dom_id, play} <- @streams.recent_plays do %>
              <div
                class="flex items-center justify-between p-2 rounded-lg bg-gray-50 dark:bg-gray-700 hover:bg-gray-100 dark:hover:bg-gray-600 cursor-pointer group"
                id={dom_id}
                phx-click="play_sound"
                phx-value-sound={play.filename}
              >
                <div class="flex items-center gap-3 min-w-0">
                  <div class="flex-shrink-0">
                    <img
                      src={get_user_avatar_from_presence(play.username, @presences)}
                      class="w-8 h-8 rounded-full"
                      alt={play.username}
                    />
                  </div>
                  <div class="min-w-0">
                    <p class="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                      {play.filename}
                    </p>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      {play.username}
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
                    {format_timestamp(play.timestamp)}
                  </span>
                  <button
                    phx-click="toggle_favorite"
                    phx-value-sound={play.filename}
                    phx-stop
                    class="text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-500 mr-2"
                  >
                    <%= if is_favorite?(@favorites, play.filename) do %>
                      <.icon name="hero-heart-solid" class="h-5 w-5 text-red-500" />
                    <% else %>
                      <.icon name="hero-heart" class="h-5 w-5" />
                    <% end %>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-200 mb-4">
            Recently Uploaded
          </h2>
          <div class="space-y-3">
            <%= for {sound_name, username, timestamp} <- @recent_uploads do %>
              <div
                class="flex items-center justify-between p-2 rounded-lg bg-gray-50 dark:bg-gray-700 hover:bg-gray-100 dark:hover:bg-gray-600 cursor-pointer group"
                id={"play-upload-#{sound_name}"}
                class="px-6"
                phx-click="play_sound"
                phx-value-sound={sound_name}
              >
                <div class="flex items-center gap-3 min-w-0">
                  <div class="flex-shrink-0">
                    <img
                      src={get_user_avatar_from_presence(username, @presences)}
                      class="w-8 h-8 rounded-full"
                      alt={username}
                    />
                  </div>
                  <div class="min-w-0">
                    <p class="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                      {sound_name}
                    </p>
                    <p class="text-xs text-gray-500 dark:text-gray-400">
                      {username}
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
                    {format_timestamp(timestamp)}
                  </span>
                  <button
                    phx-click="toggle_favorite"
                    phx-value-sound={sound_name}
                    phx-stop
                    class="text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-500 mr-2"
                  >
                    <%= if is_favorite?(@favorites, sound_name) do %>
                      <.icon name="hero-heart-solid" class="h-5 w-5 text-red-500" />
                    <% else %>
                      <.icon name="hero-heart" class="h-5 w-5" />
                    <% end %>
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp get_user_color_from_presence(username, presences) do
    presences
    |> Enum.find_value(fn {_id, presence} ->
      meta = List.first(presence.metas)

      if get_in(meta, [:user, :username]) == username do
        get_in(meta, [:user, :color]) ||
          SoundboardWeb.Live.PresenceHandler.get_user_color(username)
      end
    end) || SoundboardWeb.Live.PresenceHandler.get_user_color(username)
  end

  @impl true
  def handle_event("play_sound", %{"sound" => sound_name}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to play sounds")}

      user ->
        SoundboardWeb.AudioPlayer.play_sound(sound_name, user.username)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_favorite", %{"sound" => sound_name}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to favorite sounds")}

      user ->
        case Sound.get_sound_id(sound_name) do
          nil ->
            {:noreply, put_flash(socket, :error, "Sound not found")}

          sound_id ->
            case Favorites.toggle_favorite(user.id, sound_id) do
              {:ok, _favorite} ->
                # Get updated favorites
                updated_favorites = Favorites.list_favorites(user.id)

                # Re-fetch recent plays to trigger re-render with updated favorite states
                recent_plays =
                  Stats.get_recent_plays(limit: @recent_limit)
                  |> Enum.map(fn {filename, username, timestamp} ->
                    %{
                      id: "#{filename}-#{:erlang.system_time(:millisecond)}",
                      filename: filename,
                      username: username,
                      timestamp: timestamp
                    }
                  end)

                {:noreply,
                 socket
                 |> assign(:favorites, updated_favorites)
                 |> stream(:recent_plays, recent_plays, reset: true)
                 |> put_flash(:info, "Favorites updated!")}

              {:error, _changeset} ->
                {:noreply, put_flash(socket, :error, "Could not update favorites")}
            end
        end
    end
  end

  @impl true
  def handle_event("previous_week", _, socket) do
    {start_date, _} = socket.assigns.selected_week
    new_week = get_week_range(Date.add(start_date, -7))

    {:noreply,
     socket
     |> assign(:selected_week, new_week)
     |> assign_stats()}
  end

  @impl true
  def handle_event("next_week", _, socket) do
    {start_date, _} = socket.assigns.selected_week
    new_week = get_week_range(Date.add(start_date, 7))

    case Date.compare(elem(new_week, 1), elem(socket.assigns.current_week, 1)) do
      :gt -> {:noreply, socket}
      _ -> {:noreply, socket |> assign(:selected_week, new_week) |> assign_stats()}
    end
  end

  defp is_favorite?(favorites, sound_name) do
    case Sound.get_sound_id(sound_name) do
      nil -> false
      sound_id -> Enum.member?(favorites, sound_id)
    end
  end

  defp clear_flash_after_timeout(socket) do
    Process.send_after(self(), :clear_flash, 3000)
    socket
  end

  defp get_user_avatar_from_presence(username, presences) do
    # First try to get from presence
    presence_avatar =
      presences
      |> Enum.find_value(fn {_id, presence} ->
        meta = List.first(presence.metas)
        if get_in(meta, [:user, :username]) == username, do: get_in(meta, [:user, :avatar])
      end)

    # If not in presence, try to get from database
    case presence_avatar do
      nil ->
        case Soundboard.Repo.get_by(Soundboard.Accounts.User, username: username) do
          nil -> nil
          user -> user.avatar
        end

      avatar ->
        avatar
    end
  end
end
