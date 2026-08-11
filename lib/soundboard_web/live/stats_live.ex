defmodule SoundboardWeb.StatsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  alias SoundboardWeb.PresenceHandler
  import Phoenix.Component
  import SoundboardWeb.SoundHelpers
  alias Soundboard.{Accounts, Favorites, PubSubTopics, Sounds, Stats}
  alias SoundboardWeb.Live.Support.{FlashHelpers, NowPlayingHelpers, SoundPlayback}
  import FlashHelpers, only: [clear_flash_after_timeout: 1]

  @recent_limit 5

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      :timer.send_interval(60 * 60 * 1000, self(), :check_week_rollover)
      PubSubTopics.subscribe_playback()
      PubSubTopics.subscribe_stats()
    end

    current_week = get_week_range()

    {:ok,
     socket
     |> mount_presence(session)
     |> assign(:current_path, "/stats")
     |> assign(:current_user, get_user_from_session(session))
     |> assign(:force_update, 0)
     |> assign(:selected_week, current_week)
     |> assign(:current_week, current_week)
     |> stream_configure(:recent_plays, dom_id: &recent_play_dom_id/1)
     |> stream(:recent_plays, [])
     |> NowPlayingHelpers.assign_defaults()
     |> assign_stats()}
  end

  @impl true
  def handle_info({:sound_played, event}, socket) when is_map(event) do
    recent_plays = recent_plays()

    {:noreply,
     socket
     |> stream(:recent_plays, recent_plays, reset: true)
     |> NowPlayingHelpers.assign_from_event(event)}
  end

  @impl true
  def handle_info({:playback_stopped}, socket) do
    {:noreply, NowPlayingHelpers.clear(socket)}
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
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  defp assign_stats(socket) do
    {start_date, end_date} = socket.assigns.selected_week
    top_users = Stats.get_top_users(start_date, end_date, limit: @recent_limit)
    top_sounds = Stats.get_top_sounds(start_date, end_date, limit: @recent_limit)
    top_videos = Stats.get_top_videos(start_date, end_date, limit: @recent_limit)

    recent_plays = recent_plays()

    recent_uploads = Sounds.get_recent_uploads(limit: @recent_limit)
    favorites = get_favorites(socket.assigns.current_user)
    sound_ids_by_filename = load_sound_ids_by_filename(top_sounds, recent_plays, recent_uploads)
    avatars_by_username = load_avatars_by_username(top_users, recent_plays, recent_uploads)

    socket
    |> assign(:top_users, top_users)
    |> assign(:top_sounds, top_sounds)
    |> assign(:top_videos, top_videos)
    |> stream(:recent_plays, recent_plays, reset: true)
    |> assign(:recent_uploads, recent_uploads)
    |> assign(:favorites, favorites)
    |> assign(:sound_ids_by_filename, sound_ids_by_filename)
    |> assign(:avatars_by_username, avatars_by_username)
  end

  defp get_favorites(nil), do: []
  defp get_favorites(user), do: Favorites.list_favorites(user.id)

  defp format_timestamp(timestamp) do
    timestamp
    |> DateTime.from_naive!("Etc/UTC")
    |> Calendar.strftime("%b %d, %I:%M %p UTC")
  end

  defp get_week_range(date \\ Date.utc_today()) do
    days_since_monday = Date.day_of_week(date, :monday)
    start_date = Date.add(date, -days_since_monday + 1)
    end_date = Date.add(start_date, 6)
    {start_date, end_date}
  end

  defp format_date_range({start_date, end_date}) do
    "#{Calendar.strftime(start_date, "%b %d")} - #{Calendar.strftime(end_date, "%b %d, %Y")}"
  end

  defp date_input_value({start_date, _end_date}) do
    Date.to_iso8601(start_date)
  end

  defp parse_week_input(nil), do: :error
  defp parse_week_input(""), do: :error

  defp parse_week_input(week_value) do
    case Date.from_iso8601(week_value) do
      {:ok, date} -> {:ok, get_week_range(date)}
      _ -> :error
    end
  end

  defp get_user_color_from_presence(username, presences) do
    presences
    |> Enum.find_value(fn {_id, presence} ->
      meta = List.first(presence.metas)

      if get_in(meta, [:user, :username]) == username do
        get_in(meta, [:user, :color]) ||
          PresenceHandler.get_user_color(username)
      end
    end) || PresenceHandler.get_user_color(username)
  end

  defp handle_favorite_toggle(socket, user, sound_name) do
    case Sounds.fetch_sound_id(sound_name) do
      {:ok, sound_id} -> update_favorite(socket, user, sound_id)
      :error -> {:noreply, put_flash(socket, :error, "Sound not found")}
    end
  end

  defp update_favorite(socket, user, sound_id) do
    case Favorites.toggle_favorite(user.id, sound_id) do
      {:ok, _favorite} ->
        updated_favorites = Favorites.list_favorites(user.id)
        recent_plays = recent_plays()

        {:noreply,
         socket
         |> assign(:favorites, updated_favorites)
         |> stream(:recent_plays, recent_plays, reset: true)
         |> put_flash(:info, "Favorites updated!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Favorites.error_message(reason))}
    end
  end

  defp recent_plays do
    Stats.get_recent_activity(limit: @recent_limit)
    |> Enum.map(&map_recent_play/1)
  end

  defp map_recent_play(play) do
    %{
      id: play.id,
      filename: play.title,
      username: play.username,
      timestamp: play.timestamp,
      media_type: play.media_type,
      youtube_id: play.youtube_id,
      url: play.url
    }
  end

  defp load_sound_ids_by_filename(top_sounds, recent_plays, recent_uploads) do
    filenames =
      top_sounds
      |> Enum.map(fn {filename, _count} -> filename end)
      |> Kernel.++(
        recent_plays
        |> Enum.filter(&sound_play?/1)
        |> Enum.map(& &1.filename)
      )
      |> Kernel.++(Enum.map(recent_uploads, fn {filename, _username, _timestamp} -> filename end))
      |> Enum.uniq()

    case filenames do
      [] ->
        %{}

      _ ->
        Sounds.ids_by_filename(filenames)
    end
  end

  defp load_avatars_by_username(top_users, recent_plays, recent_uploads) do
    usernames =
      top_users
      |> Enum.map(fn {username, _count} -> username end)
      |> Kernel.++(Enum.map(recent_plays, & &1.username))
      |> Kernel.++(Enum.map(recent_uploads, fn {_filename, username, _timestamp} -> username end))
      |> Enum.uniq()

    case usernames do
      [] ->
        %{}

      _ ->
        Accounts.avatars_by_usernames(usernames)
    end
  end

  defp recent_play_dom_id(play) do
    base = slugify(play.filename)
    "recent-play-#{base}-#{play.id}"
  end

  defp sound_play?(%{media_type: "sound"}), do: true
  defp sound_play?(_), do: false

  defp youtube_play?(%{media_type: "youtube"}), do: true
  defp youtube_play?(_), do: false

  defp activity_title(play) do
    if sound_play?(play), do: display_name(play.filename), else: play.filename
  end

  defp youtube_url(%{youtube_id: youtube_id})
       when is_binary(youtube_id) and byte_size(youtube_id) > 0 do
    "https://www.youtube.com/watch?v=#{youtube_id}"
  end

  defp youtube_url(%{url: url}) when is_binary(url), do: url
  defp youtube_url(_), do: "https://www.youtube.com"

  @impl true
  def handle_event("play_sound", %{"sound" => sound_name}, socket) do
    SoundPlayback.play(socket, sound_name)
  end

  @impl true
  def handle_event("toggle_favorite", %{"sound-id" => sound_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to favorite sounds")}

      user ->
        case Integer.parse(to_string(sound_id)) do
          {id, _} -> {:noreply, update_favorite(socket, user, id)}
          :error -> {:noreply, put_flash(socket, :error, "Sound not found")}
        end
    end
  end

  @impl true
  def handle_event("toggle_favorite", %{"sound" => sound_name}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to favorite sounds")}

      user ->
        handle_favorite_toggle(socket, user, sound_name)
    end
  end

  @impl true
  def handle_event("dismiss_now_playing", _params, socket) do
    {:noreply, NowPlayingHelpers.clear(socket)}
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

  @impl true
  def handle_event("select_week", %{"week" => week_value}, socket) do
    current_week = socket.assigns.current_week

    case parse_week_input(week_value) do
      {:ok, new_week} ->
        if Date.compare(elem(new_week, 1), elem(current_week, 1)) == :gt do
          {:noreply, socket}
        else
          {:noreply,
           socket
           |> assign(:selected_week, new_week)
           |> assign_stats()}
        end

      :error ->
        {:noreply, socket}
    end
  end

  defp favorite?(favorites, sound_name, sound_ids_by_filename) do
    case Map.get(sound_ids_by_filename, sound_name) do
      nil -> false
      sound_id -> Enum.member?(favorites, sound_id)
    end
  end

  defp get_user_avatar(username, presences, avatars_by_username) do
    presences
    |> Enum.find_value(fn {_id, presence} ->
      meta = List.first(presence.metas)
      if get_in(meta, [:user, :username]) == username, do: get_in(meta, [:user, :avatar])
    end) || Map.get(avatars_by_username, username)
  end
end
