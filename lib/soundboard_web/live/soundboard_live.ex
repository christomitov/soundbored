defmodule SoundboardWeb.SoundboardLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  alias SoundboardWeb.Components.Soundboard.{DeleteModal, EditModal, UploadModal}
  import EditModal
  import DeleteModal
  import UploadModal
  alias SoundboardWeb.Presence
  alias Soundboard.{Favorites, Repo, Sound}
  require Logger
  alias SoundboardWeb.Live.{FileFilter, TagHandler, UploadHandler}
  import Ecto.Query

  import TagHandler,
    only: [
      all_tags: 1,
      count_sounds_with_tag: 2,
      tag_selected?: 2
    ]

  import FileFilter, only: [filter_files: 3]

  import SoundboardWeb.Live.UploadHandler, only: [handle_upload: 3]

  @presence_topic "soundboard:presence"
  @pubsub_topic "soundboard"

  @impl true
  def mount(_params, session, socket) do
    socket =
      if connected?(socket) do
        sounds =
          Soundboard.Sound
          |> Repo.all()
          |> Repo.preload([
            :tags,
            :user,
            user_sound_settings: [user: []]
          ])

        socket = assign(socket, :uploaded_files, sounds)
        Phoenix.PubSub.subscribe(Soundboard.PubSub, @pubsub_topic)
        Phoenix.PubSub.subscribe(Soundboard.PubSub, "soundboard:presence")
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
    |> assign(:show_modal, false)
    |> assign(:current_sound, nil)
    |> assign(:tag_input, "")
    |> assign(:tag_suggestions, [])
    |> assign(:show_upload_modal, false)
    |> assign(:source_type, "local")
    |> assign(:upload_name, "")
    |> assign(:url, "")
    |> assign(:upload_tags, [])
    |> assign(:upload_tag_input, "")
    |> assign(:upload_tag_suggestions, [])
    |> assign(:upload_ready, false)
    |> assign(:show_delete_confirm, false)
    |> assign(:selected_tags, [])
    |> assign(:is_join_sound, false)
    |> assign(:is_leave_sound, false)
    |> assign(:upload_error, nil)
    |> assign(:show_all_tags, false)
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
    {:noreply, assign(socket, :source_type, source_type)}
  end

  @impl true
  def handle_event("validate_sound", %{"_target" => ["filename"]} = params, socket) do
    Logger.info("Validating sound edit with params: #{inspect(params)}")

    # Check if filename already exists for another sound
    filename = (params["filename"] || "") <> ".mp3"
    current_sound_id = params["sound_id"]

    existing_sound =
      Sound
      |> where([s], s.filename == ^filename and s.id != ^current_sound_id)
      |> Repo.one()

    if existing_sound do
      {:noreply, put_flash(socket, :error, "A sound with that name already exists")}
    else
      {:noreply, socket}
    end
  end

  # Catch-all for other validate_sound events
  @impl true
  def handle_event("validate_sound", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_tag_list", _params, socket) do
    {:noreply, assign(socket, :show_all_tags, !socket.assigns.show_all_tags)}
  end

  @impl true
  def handle_event("toggle_edit_join_sound", _params, socket) do
    current_sound = socket.assigns.current_sound
    user_id = socket.assigns.current_user.id

    # Find or create user setting
    user_setting =
      Enum.find(current_sound.user_sound_settings, &(&1.user_id == user_id)) ||
        %Soundboard.UserSoundSetting{sound_id: current_sound.id, user_id: user_id}

    setting_params = %{
      user_id: user_id,
      sound_id: current_sound.id,
      is_join_sound: !user_setting.is_join_sound,
      is_leave_sound: user_setting.is_leave_sound
    }

    case user_setting
         |> Soundboard.UserSoundSetting.changeset(setting_params)
         |> Repo.insert_or_update() do
      {:ok, _setting} ->
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Failed to update sound settings")}
    end
  end

  @impl true
  def handle_event("toggle_edit_leave_sound", _params, socket) do
    current_sound = socket.assigns.current_sound
    user_id = socket.assigns.current_user.id

    # Find or create user setting
    user_setting =
      Enum.find(current_sound.user_sound_settings, &(&1.user_id == user_id)) ||
        %Soundboard.UserSoundSetting{sound_id: current_sound.id, user_id: user_id}

    setting_params = %{
      user_id: user_id,
      sound_id: current_sound.id,
      is_join_sound: user_setting.is_join_sound,
      is_leave_sound: !user_setting.is_leave_sound
    }

    case user_setting
         |> Soundboard.UserSoundSetting.changeset(setting_params)
         |> Repo.insert_or_update() do
      {:ok, _setting} ->
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Failed to update sound settings")}
    end
  end

  @impl true
  def handle_event("save", %{"name" => custom_name}, socket) do
    case handle_upload(socket, %{"name" => custom_name}, &handle_uploaded_entries/3) do
      {:ok, _} -> {:noreply, load_sound_files(socket)}
      {:error, _, socket} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("play", %{"name" => filename}, socket) do
    username =
      if socket.assigns.current_user,
        do: socket.assigns.current_user.username,
        else: "Anonymous"

    if socket.assigns.current_user do
      SoundboardWeb.AudioPlayer.play_sound(filename, username)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("toggle_tag_filter", %{"tag" => tag_name}, socket) do
    tag = Enum.find(all_tags(socket.assigns.uploaded_files), &(&1.name == tag_name))
    current_tag = List.first(socket.assigns.selected_tags)
    selected_tags = if current_tag && current_tag.id == tag.id, do: [], else: [tag]

    {:noreply,
     socket
     |> assign(:selected_tags, selected_tags)
     |> assign(:search_query, "")}
  end

  @impl true
  def handle_event("clear_tag_filters", _, socket) do
    {:noreply, assign(socket, :selected_tags, [])}
  end

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    sound = Soundboard.Sound.get_sound!(id)
    {:noreply, assign(socket, current_sound: sound, show_modal: true)}
  end

  @impl true
  def handle_event("save_upload", params, socket) do
    Logger.info("SAVE UPLOAD TRIGGERED with params: #{inspect(params)}")

    params =
      params
      |> Map.merge(%{
        "is_join_sound" => socket.assigns.is_join_sound,
        "is_leave_sound" => socket.assigns.is_leave_sound,
        "source_type" => socket.assigns.source_type,
        "name" => params["name"],
        "url" => params["url"]
      })

    case handle_upload(socket, params, &handle_uploaded_entries/3) do
      {:ok, _sound} ->
        {:noreply,
         socket
         |> assign(:show_upload_modal, false)
         |> assign(:upload_tags, [])
         |> assign(:upload_name, "")
         |> assign(:url, "")
         |> assign(:upload_tag_input, "")
         |> assign(:upload_tag_suggestions, [])
         |> assign(:is_join_sound, false)
         |> assign(:is_leave_sound, false)
         |> assign(:source_type, "local")
         |> load_sound_files()
         |> put_flash(:info, "Sound added successfully")}

      {:error, message, socket} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # removed obsolete "check_filename" handler; validation now covered by validate_upload

  @impl true
  def handle_event("validate_upload", %{"_target" => [field]} = params, socket)
      when field in ["name", "url", "source_type"] do
    Logger.info(
      "Validating upload (target #{field}) with params: #{inspect(Map.take(params, ["name", "url", "source_type"]))}"
    )

    # For simple text/url/source_type changes, skip re-validating upload entries
    handle_upload_validation(socket, params)
  end

  def handle_event("validate_upload", params, socket) do
    Logger.info("Validating upload with params: #{inspect(params)}")
    socket = validate_existing_entries(socket)
    handle_upload_validation(socket, params)
  end

  @impl true
  def handle_event("show_upload_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_upload_modal, true)
     |> assign(:source_type, "local")
     |> assign(:upload_tags, [])
     |> assign(:upload_name, "")
     |> assign(:upload_tag_input, "")
     |> assign(:upload_tag_suggestions, [])}
  end

  @impl true
  def handle_event("hide_upload_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_upload_modal, false)
     |> assign(:upload_tags, [])
     |> assign(:upload_name, "")
     |> assign(:upload_tag_input, "")
     |> assign(:upload_tag_suggestions, [])}
  end

  @impl true
  def handle_event("add_upload_tag", %{"key" => key, "value" => value}, socket) do
    if key == "Enter" && value != "" do
      case TagHandler.add_tag(socket, value, socket.assigns.upload_tags) do
        {:ok, socket} ->
          {:noreply,
           socket
           |> assign(:upload_tag_input, "")
           |> assign(:upload_tag_suggestions, [])}

        {:error, message} ->
          {:noreply,
           socket
           |> assign(:upload_tag_input, "")
           |> assign(:upload_tag_suggestions, [])
           |> put_flash(:error, message)}
      end
    else
      suggestions = TagHandler.search_tags(value)

      {:noreply,
       socket
       |> assign(:upload_tag_input, value)
       |> assign(:upload_tag_suggestions, suggestions)}
    end
  end

  @impl true
  def handle_event("remove_upload_tag", %{"tag" => tag_name}, socket) do
    upload_tags = Enum.reject(socket.assigns.upload_tags, &(&1.name == tag_name))
    {:noreply, assign(socket, :upload_tags, upload_tags)}
  end

  @impl true
  def handle_event("select_upload_tag_suggestion", %{"tag" => tag_name}, socket) do
    case TagHandler.add_tag(socket, tag_name, socket.assigns.upload_tags) do
      {:ok, socket} ->
        {:noreply,
         socket
         |> assign(:upload_tag_input, "")
         |> assign(:upload_tag_suggestions, [])}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:upload_tag_input, "")
         |> assign(:upload_tag_suggestions, [])
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_event("upload_tag_input", %{"key" => _key, "value" => value}, socket) do
    suggestions = TagHandler.search_tags(value)

    {:noreply,
     socket
     |> assign(:upload_tag_input, value)
     |> assign(:upload_tag_suggestions, suggestions)}
  end

  @impl true
  def handle_event("add_tag", %{"key" => key, "value" => value}, socket) do
    if key == "Enter" && value != "" do
      case TagHandler.add_tag(socket, value, socket.assigns.current_sound.tags) do
        {:ok, socket} ->
          {:noreply,
           socket
           |> assign(:tag_input, "")
           |> assign(:tag_suggestions, [])}

        {:error, message} ->
          {:noreply,
           socket
           |> assign(:tag_input, "")
           |> assign(:tag_suggestions, [])
           |> put_flash(:error, message)}
      end
    else
      suggestions = TagHandler.search_tags(value)

      {:noreply,
       socket
       |> assign(:tag_input, value)
       |> assign(:tag_suggestions, suggestions)}
    end
  end

  @impl true
  def handle_event("remove_tag", %{"tag" => tag_name}, socket) do
    sound = socket.assigns.current_sound
    tags = Enum.reject(sound.tags, &(&1.name == tag_name))

    {:ok, updated_sound} = TagHandler.update_sound_tags(sound, tags)

    {:noreply,
     socket
     |> assign(:current_sound, updated_sound)
     |> load_sound_files()}
  end

  @impl true
  def handle_event("select_tag_suggestion", %{"tag" => tag_name}, socket) do
    case TagHandler.add_tag(socket, tag_name, socket.assigns.current_sound.tags) do
      {:ok, socket} ->
        {:noreply,
         socket
         |> assign(:tag_input, "")
         |> assign(:tag_suggestions, [])}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:tag_input, "")
         |> assign(:tag_suggestions, [])
         |> put_flash(:error, message)}
    end
  end

  @impl true
  def handle_event("tag_input", %{"key" => _key, "value" => value}, socket) do
    suggestions = TagHandler.search_tags(value)

    {:noreply,
     socket
     |> assign(:tag_input, value)
     |> assign(:tag_suggestions, suggestions)}
  end

  @impl true
  def handle_event("select_tag", %{"tag" => tag_name}, socket) do
    tag = Enum.find(TagHandler.search_tags(""), &(&1.name == tag_name))
    sound = socket.assigns.current_sound

    if tag do
      case TagHandler.update_sound_tags(sound, [tag | sound.tags]) do
        {:ok, updated_sound} ->
          {:noreply,
           socket
           |> assign(:current_sound, updated_sound)
           |> assign(:tag_input, "")
           |> assign(:tag_suggestions, [])
           |> load_sound_files()}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to add tag")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Tag not found")}
    end
  end

  @impl true
  def handle_event("save_sound", params, socket) do
    handle_save_sound(
      socket.assigns.current_sound,
      socket.assigns.current_user.id,
      params,
      socket
    )
  end

  @impl true
  def handle_event("close_upload_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_upload_modal, false)
     |> assign(:upload_tags, [])
     |> assign(:upload_name, "")
     |> assign(:upload_tag_input, "")
     |> assign(:upload_tag_suggestions, [])}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, false)
     |> assign(:show_upload_modal, false)
     |> assign(:current_sound, nil)
     |> assign(:tag_input, "")
     |> assign(:tag_suggestions, [])
     |> assign(:upload_tags, [])
     |> assign(:upload_name, "")
     |> assign(:upload_tag_input, "")
     |> assign(:upload_tag_suggestions, [])}
  end

  @impl true
  def handle_event("close_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, false)
     |> assign(:current_sound, nil)
     |> assign(:tag_input, "")
     |> assign(:tag_suggestions, [])}
  end

  @impl true
  def handle_event("close_modal_key", %{"key" => "Escape"}, socket) do
    if socket.assigns.show_modal || socket.assigns.show_upload_modal do
      handle_event("close_modal", %{}, socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_upload_tag", %{"tag" => tag_name}, socket) do
    tag = Enum.find(TagHandler.search_tags(""), &(&1.name == tag_name))

    if tag do
      case TagHandler.add_tag(socket, tag_name, socket.assigns.upload_tags) do
        {:ok, socket} ->
          {:noreply,
           socket
           |> assign(:upload_tag_input, "")
           |> assign(:upload_tag_suggestions, [])}

        {:error, message} ->
          {:noreply,
           socket
           |> assign(:upload_tag_input, "")
           |> assign(:upload_tag_suggestions, [])
           |> put_flash(:error, message)}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Tag not found")}
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
             |> assign_favorites(user)
             |> put_flash(:info, "Favorites updated!")}

          {:error, message} ->
            {:noreply, put_flash(socket, :error, message)}
        end
    end
  end

  @impl true
  def handle_event("show_delete_confirm", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, true)}
  end

  @impl true
  def handle_event("hide_delete_confirm", _params, socket) do
    {:noreply, assign(socket, :show_delete_confirm, false)}
  end

  @impl true
  def handle_event("delete_sound", _params, socket) do
    sound = socket.assigns.current_sound

    # Delete from database regardless of file existence
    case Repo.delete(sound) do
      {:ok, _deleted_sound} ->
        # Only try to delete file if it's a local sound
        if sound.source_type == "local" do
          uploads_dir = Application.get_env(:soundboard, :uploads_dir, "priv/static/uploads")
          sound_path = Path.join(uploads_dir, sound.filename)
          _ = File.rm(sound_path)
        end

        {:noreply,
         socket
         |> assign(:show_modal, false)
         |> assign(:show_delete_confirm, false)
         |> assign(:current_sound, nil)
         |> load_sound_files()
         |> put_flash(:info, "Sound deleted successfully")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete sound")
         |> assign(:show_delete_confirm, false)}
    end
  end

  @impl true
  def handle_event("toggle_join_sound", _params, socket) do
    {:noreply, assign(socket, :is_join_sound, !socket.assigns.is_join_sound)}
  end

  @impl true
  def handle_event("toggle_leave_sound", _params, socket) do
    {:noreply, assign(socket, :is_leave_sound, !socket.assigns.is_leave_sound)}
  end

  @impl true
  def handle_event("play_random", _params, socket) do
    filtered_sounds =
      filter_files(
        socket.assigns.uploaded_files,
        socket.assigns.search_query,
        socket.assigns.selected_tags
      )

    case get_random_sound(filtered_sounds) do
      nil ->
        {:noreply, socket}

      sound ->
        username =
          if socket.assigns.current_user,
            do: socket.assigns.current_user.username,
            else: "Anonymous"

        # Broadcast to Discord if connected
        if connected?(socket) do
          SoundboardWeb.AudioPlayer.play_sound(sound.filename, username)
        end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("stop_sound", _params, socket) do
    # Stop browser-based sounds
    socket = push_event(socket, "stop-all-sounds", %{})

    # Stop Discord bot sounds if user is logged in
    if socket.assigns.current_user do
      SoundboardWeb.AudioPlayer.stop_sound()
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
  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
    presences = Presence.list(@presence_topic)

    {:noreply,
     socket
     |> assign(:presences, presences)
     |> assign(:presence_count, map_size(presences))}
  end

  @impl true
  def handle_info(:clear_flash, socket) do
    {:noreply, clear_flash(socket)}
  end

  @impl true
  def handle_info({:files_updated}, socket) do
    # Reload the uploaded files list with preloaded associations and proper sorting
    uploaded_files =
      Sound
      |> Repo.all()
      |> Repo.preload([:tags, :user, user_sound_settings: [user: []]])
      # Ensure consistent sorting
      |> Enum.sort_by(&String.downcase(&1.filename))

    {:noreply, assign(socket, :uploaded_files, uploaded_files)}
  end

  @impl true
  def handle_info(:load_sound_files, socket) do
    {:noreply,
     socket
     |> load_sound_files()
     |> assign(:loading_sounds, false)}
  end

  @impl true
  def handle_info({:stats_updated}, socket) do
    {:noreply, load_sound_files(socket)}
  end

  defp handle_save_sound(sound, user_id, params, socket) do
    uploads_dir = uploads_dir()
    old_path = Path.join(uploads_dir, sound.filename)
    new_filename = params["filename"] <> Path.extname(sound.filename)
    new_path = Path.join(uploads_dir, new_filename)

    # Start a transaction to handle all database updates
    case update_sound_transaction(sound, user_id, params, old_path, new_path, new_filename) do
      {:ok, _updated_sound} -> handle_successful_update(socket)
      {:error, error} -> handle_update_error(socket, error)
    end
  end

  defp error_message(changeset) do
    Enum.map_join(changeset.errors, ", ", fn {field, {msg, _opts}} ->
      "#{field} #{msg}"
    end)
  end

  defp assign_favorites(socket, nil), do: assign(socket, :favorites, [])

  defp assign_favorites(socket, user) do
    favorites = Favorites.list_favorites(user.id)
    assign(socket, :favorites, favorites)
  end

  defp load_sound_files(socket) do
    sounds =
      Sound
      |> Repo.all()
      |> Repo.preload([:tags, :user, user_sound_settings: [user: []]])
      |> Enum.sort_by(&String.downcase(&1.filename))

    assign(socket, :uploaded_files, sounds)
  end

  defp clear_flash_after_timeout(socket) do
    Process.send_after(self(), :clear_flash, 3000)
    socket
  end

  defp handle_uploaded_entries(socket, name, func) do
    Phoenix.LiveView.consume_uploaded_entries(socket, name, func)
  end

  defp get_error_message(changeset) do
    Enum.map_join(changeset.errors, ", ", fn
      {:filename, {"has already been taken", _}} -> "A sound with that name already exists"
      {:file, {"Please select a file", _}} -> "Please select a file"
      {_key, {msg, _}} -> msg
    end)
  end

  defp get_random_sound([]), do: nil

  defp get_random_sound(sounds) do
    Enum.random(sounds)
  end

  defp broadcast_update do
    Phoenix.PubSub.broadcast(Soundboard.PubSub, "soundboard", {:files_updated})
  end

  defp handle_successful_update(socket) do
    broadcast_update()

    sounds =
      Sound
      |> Repo.all()
      |> Repo.preload([
        :tags,
        :user,
        user_sound_settings: [user: []]
      ])
      |> Enum.sort_by(&String.downcase(&1.filename))

    {:noreply,
     socket
     |> put_flash(:info, "Sound updated successfully")
     |> assign(:show_modal, false)
     |> assign(:current_sound, nil)
     |> assign(:uploaded_files, sounds)}
  end

  defp handle_update_error(socket, error) do
    error_message =
      case error do
        %Ecto.Changeset{} = changeset -> error_message(changeset)
        _ -> "Failed to update sound"
      end

    {:noreply,
     socket
     |> put_flash(:error, "Error updating sound: #{error_message}")}
  end

  defp validate_existing_entries(socket) do
    if socket.assigns.uploads.audio.entries == [] do
      socket
    else
      validate_audio_entries(socket)
    end
  end

  defp handle_upload_validation(socket, params) do
    params = normalize_upload_params(socket, params)

    case UploadHandler.validate_upload(socket, params) do
      {:ok, _socket} ->
        {:noreply, assign_upload_params(socket, params, nil)}

      {:error, changeset} ->
        {:noreply, assign_upload_params(socket, params, get_error_message(changeset))}
    end
  end

  defp normalize_upload_params(socket, params) do
    params
    |> Map.put_new("source_type", socket.assigns.source_type)
    |> Map.put_new("name", socket.assigns.upload_name)
    |> Map.put_new("url", socket.assigns.url)
  end

  defp assign_upload_params(socket, params, error) do
    socket
    |> assign(:upload_error, error)
    |> assign(:upload_name, params["name"] || socket.assigns.upload_name)
    |> assign(:url, params["url"] || socket.assigns.url)
    |> assign(:source_type, params["source_type"] || socket.assigns.source_type)
  end

  defp update_sound_transaction(sound, user_id, params, old_path, new_path, new_filename) do
    Repo.transaction(fn ->
      sound_params = %{
        filename: new_filename,
        source_type: params["source_type"] || sound.source_type,
        url: params["url"]
      }

      updated_sound =
        case Sound.changeset(sound, sound_params) |> Repo.update() do
          {:ok, updated_sound} -> update_user_settings(sound, user_id, updated_sound, params)
          {:error, changeset} -> Repo.rollback(changeset)
        end

      case maybe_rename_local_file(sound, old_path, new_path) do
        :ok -> updated_sound
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  defp maybe_rename_local_file(%{source_type: "local"} = sound, old_path, new_path) do
    cond do
      sound.filename == Path.basename(new_path) ->
        :ok

      old_path == new_path ->
        :ok

      not File.exists?(old_path) ->
        Logger.error("Source file not found: #{old_path}")
        {:error, "Source file not found"}

      true ->
        case File.rename(old_path, new_path) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("File rename failed: #{inspect(reason)}")
            {:error, "Failed to rename file: #{inspect(reason)}"}
        end
    end
  end

  defp maybe_rename_local_file(_, _, _), do: :ok

  defp uploads_dir do
    Application.get_env(:soundboard, :uploads_dir, "priv/static/uploads")
  end

  defp update_user_settings(sound, user_id, updated_sound, params) do
    # Find or create user setting
    user_setting =
      Enum.find(sound.user_sound_settings, &(&1.user_id == user_id)) ||
        %Soundboard.UserSoundSetting{sound_id: sound.id, user_id: user_id}

    # Update the settings using our UserSoundSetting changeset
    setting_params = %{
      user_id: user_id,
      sound_id: sound.id,
      is_join_sound: params["is_join_sound"] == "true",
      is_leave_sound: params["is_leave_sound"] == "true"
    }

    case user_setting
         |> Soundboard.UserSoundSetting.changeset(setting_params)
         |> Repo.insert_or_update() do
      {:ok, _setting} ->
        updated_sound

      {:error, changeset} ->
        Logger.error("Failed to update user settings: #{inspect(changeset)}")
        Repo.rollback(changeset)
    end
  end

  defp validate_audio(entry, _socket) do
    case entry.client_type do
      type when type in ~w(audio/mpeg audio/wav audio/ogg audio/x-m4a) ->
        {:ok, entry}

      _ ->
        {:error, "Invalid file type"}
    end
  end

  defp validate_audio_entries(socket) do
    case socket.assigns.uploads.audio.entries do
      [entry | _] ->
        case validate_audio(entry, socket) do
          {:ok, _} -> socket
          {:error, error} -> put_flash(socket, :error, error)
        end

      _ ->
        socket
    end
  end

  defp handle_progress(:audio, _entry, socket) do
    {:noreply, socket}
  end
end
