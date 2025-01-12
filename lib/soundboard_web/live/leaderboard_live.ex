defmodule SoundboardWeb.LeaderboardLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  alias Soundboard.{Stats, Favorites, Sound}
  require Logger

  @pubsub_topic "soundboard"

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      :timer.send_interval(60 * 60 * 1000, self(), :check_week_rollover)
      Phoenix.PubSub.subscribe(Soundboard.PubSub, @presence_topic)
      Phoenix.PubSub.subscribe(Soundboard.PubSub, "sounds")
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
     |> assign(:recent_uploads, Sound.get_recent_uploads())
     |> assign_stats()}
  end

  @impl true
  def handle_info(:update_stats, socket) do
    {:noreply, assign_stats(socket)}
  end

  @impl true
  def handle_info({:sound_played, %{filename: filename, played_by: username}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "#{username} played #{filename}")
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info({:play, sound_name, username}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "#{username} played #{sound_name}")
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_info(:check_week_rollover, socket) do
    current_range = get_week_range()

    if current_range != socket.assigns.week_range do
      # New week has started, reset stats
      Stats.reset_weekly_stats()

      {:noreply,
       socket
       |> assign(:week_range, current_range)
       |> assign_stats()
       |> put_flash(:info, "Stats have been reset for the new week!")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:error, message}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> clear_flash_after_timeout()}
  end

  defp assign_stats(socket) do
    user_id = socket.assigns.current_user.id
    {start_date, end_date} = socket.assigns.selected_week

    socket
    |> assign(:top_users, Stats.get_top_users(start_date, end_date))
    |> assign(:top_sounds, Stats.get_top_sounds(start_date, end_date))
    |> assign(:recent_plays, Stats.get_recent_plays(start_date, end_date))
    |> assign(:favorites, Favorites.list_favorites(user_id))
  end

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

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100 mb-4">Top Sounds</h2>
          <div class="space-y-2">
            <%= for {sound_name, count} <- @top_sounds do %>
              <div class="flex justify-between items-center">
                <div class="flex items-center gap-2">
                  <button
                    phx-click="play_sound"
                    phx-value-sound={sound_name}
                    phx-hook="ClickFeedback"
                    id={"play-top-#{sound_name}"}
                    class="text-gray-800 dark:text-gray-200 hover:text-blue-500 dark:hover:text-blue-400"
                  >
                    {sound_name}
                  </button>
                  <button
                    phx-click="toggle_favorite"
                    phx-value-sound={sound_name}
                    class="text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-500"
                  >
                    <%= if is_favorite?(@favorites, sound_name) do %>
                      <.icon name="hero-heart-solid" class="h-5 w-5 text-red-500" />
                    <% else %>
                      <.icon name="hero-heart" class="h-5 w-5" />
                    <% end %>
                  </button>
                </div>
                <span class="text-gray-600 dark:text-gray-400">{count} plays</span>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <div class="mt-8 grid grid-cols-1 md:grid-cols-2 gap-8">
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100 mb-4">Recent Plays</h2>
          <div class="space-y-2">
            <%= for {sound_name, username, timestamp} <- @recent_plays do %>
              <div class="flex justify-between items-center">
                <div class="flex items-center gap-2">
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
                  <button
                    phx-click="play_sound"
                    phx-value-sound={sound_name}
                    phx-hook="ClickFeedback"
                    id={"play-recent-#{sound_name}"}
                    class="text-gray-800 dark:text-gray-200 hover:text-blue-500 dark:hover:text-blue-400"
                  >
                    {sound_name}
                  </button>
                  <button
                    phx-click="toggle_favorite"
                    phx-value-sound={sound_name}
                    class="text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-500"
                  >
                    <%= if is_favorite?(@favorites, sound_name) do %>
                      <.icon name="hero-heart-solid" class="h-5 w-5 text-red-500" />
                    <% else %>
                      <.icon name="hero-heart" class="h-5 w-5" />
                    <% end %>
                  </button>
                </div>
                <span class="text-sm text-gray-600 dark:text-gray-400">
                  {format_timestamp(timestamp)}
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h2 class="text-xl font-semibold text-gray-800 dark:text-gray-100 mb-4">
            Recently Uploaded
          </h2>
          <div class="space-y-2">
            <%= for {sound_name, username, timestamp} <- @recent_uploads do %>
              <div class="flex justify-between items-center">
                <div class="flex items-center gap-2">
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
                  <button
                    phx-click="play_sound"
                    phx-value-sound={sound_name}
                    phx-hook="ClickFeedback"
                    id={"play-upload-#{sound_name}"}
                    class="text-gray-800 dark:text-gray-200 hover:text-blue-500 dark:hover:text-blue-400"
                  >
                    {sound_name}
                  </button>
                  <button
                    phx-click="toggle_favorite"
                    phx-value-sound={sound_name}
                    class="text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-500"
                  >
                    <%= if is_favorite?(@favorites, sound_name) do %>
                      <.icon name="hero-heart-solid" class="h-5 w-5 text-red-500" />
                    <% else %>
                      <.icon name="hero-heart" class="h-5 w-5" />
                    <% end %>
                  </button>
                </div>
                <span class="text-sm text-gray-600 dark:text-gray-400">
                  {format_timestamp(timestamp)}
                </span>
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
    username = socket.assigns.current_user.username

    if socket.assigns.current_user do
      Soundboard.Stats.track_play(sound_name, socket.assigns.current_user.id)
    end

    # Play the sound through AudioPlayer
    SoundboardWeb.AudioPlayer.play_sound(sound_name, username)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_favorite", %{"sound" => sound_name}, socket) do
    user_id = socket.assigns.current_user.id

    case Sound.get_sound_id(sound_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Sound not found")}

      sound_id ->
        case Favorites.toggle_favorite(user_id, sound_id) do
          {:ok, _favorite} ->
            {:noreply, assign(socket, :favorites, Favorites.list_favorites(user_id))}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not update favorites")}
        end
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
    presences
    |> Enum.find_value(fn {_id, presence} ->
      meta = List.first(presence.metas)
      if get_in(meta, [:user, :username]) == username, do: get_in(meta, [:user, :avatar])
    end)
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
end
