defmodule SoundboardWeb.SettingsLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.Support.PresenceLive
  import Phoenix.Controller, only: [get_csrf_token: 0]
  alias Soundboard.Accounts.ApiTokens
  alias Soundboard.{Favorites, PublicURL, PubSubTopics}
  alias Soundboard.YouTube.Cookies
  alias SoundboardWeb.Live.Support.NowPlayingHelpers

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      PubSubTopics.subscribe_playback()
    end

    user = get_user_from_session(session)

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/settings")
      |> assign(:current_user, user)
      |> assign(:settings_tab, "appearance")
      |> assign(:api_docs_open, false)
      |> assign(:tokens, [])
      |> assign(:new_token, nil)
      |> assign(:base_url, PublicURL.current())
      |> assign(:favorites, favorites_for(user))
      |> assign(:cookie_status, Cookies.status())
      |> assign(:cookie_paste, "")
      |> allow_upload(:youtube_cookies,
        accept: ~w(.txt text/plain),
        max_entries: 1,
        max_file_size: 1_000_000
      )
      |> NowPlayingHelpers.assign_defaults()

    {:ok, load_tokens(socket)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :base_url, PublicURL.from_uri_or_current(uri))}
  end

  @impl true
  def handle_event("select_settings_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :settings_tab, normalize_tab(tab))}
  end

  def handle_event("toggle_api_docs", _params, socket) do
    {:noreply, assign(socket, :api_docs_open, !socket.assigns.api_docs_open)}
  end

  @impl true
  def handle_event(
        "create_token",
        %{"label" => label},
        %{assigns: %{current_user: user}} = socket
      ) do
    case ApiTokens.generate_token(user, %{label: String.trim(label)}) do
      {:ok, raw, _token} ->
        {:noreply,
         socket
         |> assign(:settings_tab, "api")
         |> assign(:new_token, raw)
         |> load_tokens()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create token")}
    end
  end

  @impl true
  def handle_event("revoke_token", %{"id" => id}, %{assigns: %{current_user: user}} = socket) do
    case ApiTokens.revoke_token(user, id) do
      {:ok, _} -> {:noreply, socket |> load_tokens() |> put_flash(:info, "Token revoked")}
      {:error, :forbidden} -> {:noreply, put_flash(socket, :error, "Not allowed")}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "Token not found")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to revoke token")}
    end
  end

  @impl true
  def handle_event("toggle_favorite", %{"sound-id" => sound_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "You must be logged in to favorite sounds")}

      user ->
        case Favorites.toggle_favorite(user.id, sound_id) do
          {:ok, _} ->
            {:noreply, assign(socket, :favorites, favorites_for(user))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Favorites.error_message(reason))}
        end
    end
  end

  @impl true
  def handle_event("dismiss_now_playing", _params, socket) do
    {:noreply, NowPlayingHelpers.clear(socket)}
  end

  def handle_event("update_cookie_paste", %{"cookies" => cookies}, socket) do
    {:noreply, assign(socket, :cookie_paste, cookies)}
  end

  def handle_event("save_cookies_paste", %{"cookies" => cookies}, socket) do
    case Cookies.save(cookies) do
      {:ok, status} ->
        {:noreply,
         socket
         |> assign(:cookie_status, status)
         |> assign(:cookie_paste, "")
         |> put_flash(:info, "YouTube cookies saved and validated")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("save_cookies_upload", _params, socket) do
    results =
      consume_uploaded_entries(socket, :youtube_cookies, fn %{path: path}, _entry ->
        save_uploaded_cookies(path)
      end)

    case results do
      [{:saved, status} | _] ->
        {:noreply,
         socket
         |> assign(:cookie_status, status)
         |> put_flash(:info, "YouTube cookies uploaded and validated")}

      [{:error, reason} | _] ->
        {:noreply, put_flash(socket, :error, reason)}

      _ ->
        {:noreply, put_flash(socket, :error, "Please choose a cookies.txt file to upload")}
    end
  end

  def handle_event("clear_cookies", _params, socket) do
    Cookies.clear()

    {:noreply,
     socket
     |> assign(:cookie_status, Cookies.status())
     |> put_flash(:info, "YouTube cookies cleared")}
  end

  def handle_event("validate_cookies_upload", _params, socket), do: {:noreply, socket}

  defp save_uploaded_cookies(path) do
    case File.read(path) do
      {:ok, contents} -> normalize_cookie_save(Cookies.save(contents))
      {:error, reason} -> {:ok, {:error, "Failed to read upload: #{inspect(reason)}"}}
    end
  end

  defp normalize_cookie_save({:ok, status}), do: {:ok, {:saved, status}}
  defp normalize_cookie_save({:error, reason}), do: {:ok, {:error, reason}}

  @impl true
  def handle_info({:sound_played, event}, socket) when is_map(event) do
    {:noreply, NowPlayingHelpers.assign_from_event(socket, event)}
  end

  @impl true
  def handle_info({:playback_stopped}, socket) do
    {:noreply, NowPlayingHelpers.clear(socket)}
  end

  @impl true
  def handle_info({:error, _message}, socket), do: {:noreply, socket}

  defp favorites_for(nil), do: []
  defp favorites_for(user), do: Favorites.list_favorites(user.id)

  defp load_tokens(%{assigns: %{current_user: nil}} = socket), do: socket

  defp load_tokens(%{assigns: %{current_user: user}} = socket) do
    tokens = ApiTokens.list_tokens(user)

    socket
    |> assign(:tokens, tokens)
    |> assign(:example_token, socket.assigns[:new_token])
  end

  defp normalize_tab(tab) when tab in ["appearance", "api", "youtube"], do: tab
  defp normalize_tab(_), do: "appearance"

  defp format_dt(nil), do: nil
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
