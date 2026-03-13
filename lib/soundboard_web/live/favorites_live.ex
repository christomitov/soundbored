defmodule SoundboardWeb.FavoritesLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  alias Soundboard.{Favorites, PubSubTopics}
  alias SoundboardWeb.Live.Support.{FlashHelpers, SoundPlayback}
  import FlashHelpers, only: [flash_sound_played: 2, clear_flash_after_timeout: 1]
  require Logger

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      PubSubTopics.subscribe_files()
      PubSubTopics.subscribe_playback()
    end

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/favorites")
      |> assign(:current_user, get_user_from_session(session))
      |> assign(:max_favorites, Favorites.max_favorites())

    {:ok, assign_favorites_state(socket, socket.assigns[:current_user])}
  end

  @impl true
  def handle_event("play", %{"name" => filename}, socket) do
    SoundPlayback.play(socket, filename)
  end

  @impl true
  def handle_event("toggle_favorite", %{"sound-id" => sound_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to favorite sounds")}

      user ->
        case Favorites.toggle_favorite(user.id, sound_id) do
          {:ok, _favorite} ->
            {:noreply,
             socket
             |> assign_favorites_state(user)
             |> put_flash(:info, "Favorites updated!")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Favorites.error_message(reason))}
        end
    end
  end

  @impl true
  def handle_info({:sound_played, %{filename: _, played_by: _} = event}, socket) do
    {:noreply, flash_sound_played(socket, event)}
  end

  @impl true
  def handle_info({:sound_played, filename}, socket) when is_binary(filename) do
    username =
      case SoundPlayback.current_username(socket) do
        {:ok, current_username} -> current_username
        :error -> "Someone"
      end

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
    {:noreply, assign_favorites_state(socket, socket.assigns[:current_user])}
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_info({:stats_updated}, socket) do
    {:noreply, assign_favorites_state(socket, socket.assigns[:current_user])}
  end

  defp assign_favorites_state(socket, nil) do
    assign(socket, favorites: [], sounds_with_tags: [])
  end

  defp assign_favorites_state(socket, user) do
    favorites = Favorites.list_favorites(user.id)

    assign(socket,
      favorites: favorites,
      sounds_with_tags: Favorites.list_favorite_sounds_with_tags(user.id)
    )
  end
end
