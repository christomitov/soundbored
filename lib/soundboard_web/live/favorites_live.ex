defmodule SoundboardWeb.FavoritesLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  import Ecto.Query
  alias Soundboard.Accounts.Tenants
  alias Soundboard.{Favorites, Repo, Sound, Stats}
  alias Soundboard.PubSubTopics
  alias SoundboardWeb.Live.TenantHelpers
  require Logger

  @pubsub_topic "soundboard"

  @impl true
  def mount(_params, session, socket) do
    current_user = get_user_from_session(session)
    tenant_id = TenantHelpers.tenant_id_from_session(session, current_user)
    tenant = Tenants.get_tenant!(tenant_id)

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/favorites")
      |> assign(:current_user, current_user)
      |> assign(:current_tenant, tenant)
      |> assign(:current_tenant_id, tenant.id)
      |> assign(:max_favorites, Favorites.max_favorites())

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Soundboard.PubSub, Stats.stats_topic(tenant.id))
        Phoenix.PubSub.subscribe(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant.id))
        Phoenix.PubSub.subscribe(Soundboard.PubSub, @pubsub_topic)
        socket
      else
        socket
      end

    {:ok, load_favorites(socket)}
  end

  @impl true
  def handle_event("play", %{"name" => filename}, socket) do
    username =
      if socket.assigns.current_user,
        do: socket.assigns.current_user.username,
        else: "Anonymous"

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
            {:noreply,
             socket
             |> load_favorites()
             |> put_flash(:info, "Favorites updated!")}

          {:error, message} ->
            {:noreply, put_flash(socket, :error, message)}
        end
    end
  end

  @impl true
  def handle_info(
        {:sound_played, %{tenant_id: tenant_id, filename: filename, played_by: username}},
        socket
      ) do
    if tenant_matches?(socket, tenant_id) do
      {:noreply,
       socket
       |> put_flash(:info, "#{username} played #{filename}")
       |> clear_flash_after_timeout()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:sound_played, payload}, socket) do
    handle_info(
      {:sound_played, Map.put(payload, :tenant_id, socket.assigns.current_tenant_id)},
      socket
    )
  end

  @impl true
  def handle_info({:error, message}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, message)
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info({:files_updated, tenant_id}, socket) do
    if tenant_matches?(socket, tenant_id) do
      {:noreply, load_favorites(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:files_updated}, socket) do
    handle_info({:files_updated, nil}, socket)
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_info({:stats_updated, tenant_id}, socket) do
    if tenant_matches?(socket, tenant_id) do
      {:noreply, load_favorites(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stats_updated}, socket) do
    handle_info({:stats_updated, nil}, socket)
  end

  defp load_favorites(socket) do
    case socket.assigns[:current_user] do
      nil ->
        socket
        |> assign(:favorites, [])
        |> assign(:sounds_with_tags, [])

      user ->
        favorites = Favorites.list_favorites(user.id)

        sounds_with_tags =
          Sound.with_tags()
          |> where([s], s.tenant_id == ^socket.assigns.current_tenant_id)
          |> Repo.all()
          |> Enum.filter(&(&1.id in favorites))
          |> Enum.sort_by(&String.downcase(&1.filename))

        socket
        |> assign(:favorites, favorites)
        |> assign(:sounds_with_tags, sounds_with_tags)
    end
  end

  defp tenant_matches?(_socket, nil), do: true
  defp tenant_matches?(socket, tenant_id), do: socket.assigns.current_tenant_id == tenant_id

  defp clear_flash_after_timeout(socket) do
    Process.send_after(self(), :clear_flash, 3000)
    socket
  end
end
