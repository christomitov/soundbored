defmodule SoundboardWeb.FavoritesLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  alias Soundboard.{Favorites, Sound}
  require Logger

  @pubsub_topic "soundboard"

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, @pubsub_topic)
    end

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/favorites")
      |> assign(:current_user, get_user_from_session(session))
      |> assign(:max_favorites, Favorites.max_favorites())

    if socket.assigns[:current_user] do
      favorites = Favorites.list_favorites(socket.assigns.current_user.id)

      sounds_with_tags =
        Sound.with_tags()
        |> Soundboard.Repo.all()
        |> Enum.filter(&(&1.id in favorites))

      {:ok, assign(socket, favorites: favorites, sounds_with_tags: sounds_with_tags)}
    else
      {:ok, assign(socket, favorites: [], sounds_with_tags: [])}
    end
  end

  @impl true
  def handle_event("play", %{"name" => filename}, socket) do
    username =
      if socket.assigns.current_user,
        do: socket.assigns.current_user.username,
        else: "Anonymous"

    if socket.assigns.current_user do
      Soundboard.Stats.track_play(filename, socket.assigns.current_user.id)
    end

    SoundboardWeb.AudioPlayer.play_sound(filename, username)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_favorite", %{"sound-id" => sound_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to favorite sounds")}

      user ->
        case Favorites.toggle_favorite(user.id, sound_id) do
          {:ok, _favorite} ->
            favorites = Favorites.list_favorites(user.id)

            sounds_with_tags =
              Sound.with_tags()
              |> Soundboard.Repo.all()
              |> Enum.filter(&(&1.id in favorites))

            {:noreply,
             socket
             |> assign(favorites: favorites, sounds_with_tags: sounds_with_tags)
             |> put_flash(:info, "Favorites updated!")}

          {:error, message} ->
            {:noreply, put_flash(socket, :error, message)}
        end
    end
  end

  @impl true
  def handle_info({:sound_played, %{filename: filename, played_by: username}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "#{username} played #{filename}")
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info({:sound_played, filename}, socket) when is_binary(filename) do
    username =
      if socket.assigns.current_user,
        do: socket.assigns.current_user.username,
        else: "Anonymous"

    {:noreply,
     socket
     |> put_flash(:info, "#{username} played #{filename}")
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info({:error, message}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info({:files_updated}, socket) do
    if socket.assigns[:current_user] do
      favorites = Favorites.list_favorites(socket.assigns.current_user.id)

      sounds_with_tags =
        Sound.with_tags()
        |> Soundboard.Repo.all()
        |> Enum.filter(&(&1.id in favorites))

      {:noreply, assign(socket, favorites: favorites, sounds_with_tags: sounds_with_tags)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  defp clear_flash_after_timeout(socket) do
    Process.send_after(self(), :clear_flash, 3000)
    socket
  end
end
