defmodule SoundboardWeb.SoundboardLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  alias SoundboardWeb.Components.Soundboard.{DeleteModal, EditModal, UploadModal}
  import EditModal
  import DeleteModal
  import UploadModal
  import SoundboardWeb.Components.Soundboard.TagComponents, only: [tag_filter_button: 1]
  alias Soundboard.{Favorites, PubSubTopics, Sounds}
  alias SoundboardWeb.Live.{LiveTags, SoundPlayback}
  alias SoundboardWeb.Live.SoundboardLive.{EditFlow, UploadFlow}
  alias SoundboardWeb.Soundboard.SoundFilter
  import LiveTags, only: [all_tags: 1, tag_selected?: 2]

  import SoundFilter, only: [filter_sounds: 3]

  @impl true
  def mount(_params, session, socket) do
    socket =
      if connected?(socket) do
        PubSubTopics.subscribe_files()
        PubSubTopics.subscribe_playback()
        send(self(), :load_sound_files)
        socket
      else
        socket
      end

    socket =
      socket
      |> mount_presence(session)
      |> assign(:current_path, "/")
      |> assign(:current_user, get_user_from_session(session))
      |> assign_initial_state()
      |> assign_favorites(get_user_from_session(session))

    if socket.assigns.flash do
      Process.send_after(self(), :clear_flash, 3000)
    end

    {:ok, socket}
  end

  defp assign_initial_state(socket) do
    socket
    |> assign(:uploaded_files, [])
    |> assign(:loading_sounds, true)
    |> assign(:search_query, "")
    |> assign(:editing, nil)
    |> assign(:selected_tags, [])
    |> assign(:show_all_tags, false)
    |> UploadFlow.assign_defaults()
    |> EditFlow.assign_defaults()
    |> allow_upload(:audio,
      accept: ~w(audio/mpeg audio/wav audio/ogg audio/x-m4a),
      max_entries: 1,
      max_file_size: 25_000_000,
      auto_upload: false,
      progress: &handle_progress/3,
      accept_errors: [
        too_large: "File is too large (max 25MB)",
        not_accepted: "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."
      ]
    )
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("change_source_type", %{"source_type" => source_type}, socket) do
    UploadFlow.change_source_type(socket, source_type)
  end

  @impl true
  def handle_event("validate_sound", params, socket) do
    EditFlow.validate_sound(socket, params)
  end

  @impl true
  def handle_event("toggle_tag_list", _params, socket) do
    {:noreply, assign(socket, :show_all_tags, !socket.assigns.show_all_tags)}
  end

  @impl true
  def handle_event("play", %{"name" => filename}, socket) do
    SoundPlayback.play(socket, filename)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("toggle_tag_filter", %{"tag" => tag_name}, socket) do
    case Enum.find(all_tags(socket.assigns.uploaded_files), &(&1.name == tag_name)) do
      nil ->
        {:noreply, socket}

      tag ->
        current_tag = List.first(socket.assigns.selected_tags)
        selected_tags = if current_tag && current_tag.id == tag.id, do: [], else: [tag]

        {:noreply,
         socket
         |> assign(:selected_tags, selected_tags)
         |> assign(:search_query, "")}
    end
  end

  @impl true
  def handle_event("clear_tag_filters", _, socket) do
    {:noreply, assign(socket, :selected_tags, [])}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    EditFlow.open_modal(socket, id)
  end

  @impl true
  def handle_event("save_upload", params, socket) do
    UploadFlow.save(socket, params, &Phoenix.LiveView.consume_uploaded_entries/3)
  end

  @impl true
  def handle_event("validate_upload", params, socket) do
    UploadFlow.validate(socket, params)
  end

  @impl true
  def handle_event("show_upload_modal", _params, socket) do
    UploadFlow.show_modal(socket)
  end

  @impl true
  def handle_event("hide_upload_modal", _params, socket) do
    UploadFlow.hide_modal(socket)
  end

  @impl true
  def handle_event("add_upload_tag", %{"key" => key, "value" => value}, socket) do
    UploadFlow.add_tag(socket, key, value)
  end

  @impl true
  def handle_event("remove_upload_tag", %{"tag" => tag_name}, socket) do
    UploadFlow.remove_tag(socket, tag_name)
  end

  @impl true
  def handle_event("select_upload_tag_suggestion", %{"tag" => tag_name}, socket) do
    UploadFlow.select_tag_suggestion(socket, tag_name)
  end

  @impl true
  def handle_event("upload_tag_input", %{"key" => _key, "value" => value}, socket) do
    UploadFlow.update_tag_input(socket, value)
  end

  @impl true
  def handle_event("add_tag", %{"key" => key, "value" => value}, socket) do
    EditFlow.add_tag(socket, key, value)
  end

  @impl true
  def handle_event("remove_tag", %{"tag" => tag_name}, socket) do
    EditFlow.remove_tag(socket, tag_name)
  end

  @impl true
  def handle_event("select_tag_suggestion", %{"tag" => tag_name}, socket) do
    EditFlow.select_tag_suggestion(socket, tag_name)
  end

  @impl true
  def handle_event("tag_input", %{"key" => _key, "value" => value}, socket) do
    EditFlow.update_tag_input(socket, value)
  end

  @impl true
  def handle_event("select_tag", %{"tag" => tag_name}, socket) do
    EditFlow.select_tag(socket, tag_name)
  end

  @impl true
  def handle_event("save_sound", params, socket) do
    EditFlow.save_sound(socket, params)
  end

  @impl true
  def handle_event("close_upload_modal", _params, socket) do
    UploadFlow.hide_modal(socket)
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> UploadFlow.close_modal()
     |> EditFlow.close_modal()}
  end

  @impl true
  def handle_event("close_modal_key", %{"key" => "Escape"}, socket) do
    edit_open = socket.assigns[:edit_state] && socket.assigns.edit_state.show_modal
    upload_open = socket.assigns[:upload_state] && socket.assigns.upload_state.show_upload_modal

    if edit_open || upload_open do
      handle_event("close_modal", %{}, socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_upload_tag", %{"tag" => tag_name}, socket) do
    UploadFlow.select_tag(socket, tag_name)
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
             |> assign_favorites(user)
             |> put_flash(:info, "Favorites updated!")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, Favorites.error_message(reason))}
        end
    end
  end

  @impl true
  def handle_event("show_delete_confirm", _params, socket) do
    EditFlow.show_delete_confirm(socket)
  end

  @impl true
  def handle_event("hide_delete_confirm", _params, socket) do
    EditFlow.hide_delete_confirm(socket)
  end

  @impl true
  def handle_event("delete_sound", _params, socket) do
    EditFlow.delete_sound(socket)
  end

  @impl true
  def handle_event("toggle_join_sound", _params, socket) do
    UploadFlow.toggle_join_sound(socket)
  end

  @impl true
  def handle_event("toggle_leave_sound", _params, socket) do
    UploadFlow.toggle_leave_sound(socket)
  end

  @impl true
  def handle_event("update_volume", %{"volume" => volume, "target" => "edit"}, socket) do
    EditFlow.update_volume(socket, volume)
  end

  @impl true
  def handle_event("update_volume", %{"volume" => volume, "target" => "upload"}, socket) do
    UploadFlow.update_volume(socket, volume)
  end

  @impl true
  def handle_event("update_volume", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("play_random", _params, socket) do
    filtered_sounds =
      filter_sounds(
        socket.assigns.uploaded_files,
        socket.assigns.search_query,
        socket.assigns.selected_tags
      )

    case get_random_sound(filtered_sounds) do
      nil ->
        {:noreply, socket}

      sound ->
        SoundPlayback.play(socket, sound.filename)
    end
  end

  @impl true
  def handle_event("stop_sound", _params, socket) do
    # Stop browser-based sounds
    socket = push_event(socket, "stop-all-sounds", %{})

    # Stop Discord bot sounds if user is logged in
    if socket.assigns.current_user do
      Soundboard.AudioPlayer.stop_sound()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  @impl true
  def handle_info({:sound_played, %{filename: filename, played_by: username}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "#{username} played #{filename}")
     |> clear_flash_after_timeout()}
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_info({:files_updated}, socket) do
    {:noreply, load_sound_files(socket)}
  end

  @impl true
  def handle_info(:load_sound_files, socket) do
    {:noreply,
     socket
     |> load_sound_files()
     |> assign(:loading_sounds, false)}
  end

  defp assign_favorites(socket, nil), do: assign(socket, :favorites, [])

  defp assign_favorites(socket, user) do
    favorites = Favorites.list_favorites(user.id)
    assign(socket, :favorites, favorites)
  end

  defp load_sound_files(socket) do
    assign(socket, :uploaded_files, Sounds.list_detailed())
  end

  defp clear_flash_after_timeout(socket) do
    Process.send_after(self(), :clear_flash, 3000)
    socket
  end

  defp get_random_sound([]), do: nil

  defp get_random_sound(sounds) do
    Enum.random(sounds)
  end

  defp handle_progress(:audio, _entry, socket) do
    {:noreply, socket}
  end
end
