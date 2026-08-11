defmodule SoundboardWeb.FavoritesLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  alias Soundboard.{Favorites, PubSubTopics}
  alias SoundboardWeb.Live.Support.{FlashHelpers, NowPlayingHelpers, SoundPlayback}
  import FlashHelpers, only: [clear_flash_after_timeout: 1]
  import SoundboardWeb.Components.Soundboard.Waveform, only: [waveform: 1]

  @pad_keys ~w(1 2 3 4 5 6 7 8 9 0 Q W E R T Y U I O P A S D F G H J K L Z X C V B N M)

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
      |> NowPlayingHelpers.assign_defaults()

    {:ok, assign_favorites_state(socket, socket.assigns[:current_user])}
  end

  @impl true
  def handle_event("play", %{"name" => filename}, socket) do
    SoundPlayback.play(socket, filename)
  end

  @impl true
  def handle_event("play_random", _params, socket) do
    case socket.assigns.sounds_with_tags do
      [] ->
        {:noreply, socket}

      sounds ->
        sound = Enum.random(sounds)
        SoundPlayback.play(socket, sound.filename)
    end
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
  def handle_event("dismiss_now_playing", _params, socket) do
    {:noreply, NowPlayingHelpers.clear(socket)}
  end

  @impl true
  def handle_info({:sound_played, %{filename: _, played_by: _} = event}, socket) do
    {:noreply, NowPlayingHelpers.assign_from_event(socket, event)}
  end

  @impl true
  def handle_info({:sound_played, filename}, socket) when is_binary(filename) do
    username =
      case SoundPlayback.current_username(socket) do
        {:ok, current_username} -> current_username
        :error -> "Someone"
      end

    {:noreply,
     NowPlayingHelpers.assign_from_event(socket, %{filename: filename, played_by: username})}
  end

  @impl true
  def handle_info({:playback_stopped}, socket) do
    {:noreply, NowPlayingHelpers.clear(socket)}
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

  defp pad_key(index) when is_integer(index) and index >= 0 do
    Enum.at(@pad_keys, rem(index, length(@pad_keys)))
  end
end
