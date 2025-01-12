defmodule SoundboardWeb.SoundboardLive do
  use SoundboardWeb, :live_view
  use SoundboardWeb.Live.PresenceLive
  alias SoundboardWeb.Components.Soundboard.{EditModal, DeleteModal, UploadModal}
  import EditModal
  import DeleteModal
  import UploadModal
  alias SoundboardWeb.Presence
  alias Soundboard.{Repo, Sound, Favorites}
  require Logger
  alias SoundboardWeb.Live.{UploadHandler, FileHandler, TagHandler, PresenceHandler, FileFilter}
  import Ecto.Query

  import TagHandler,
    only: [
      all_tags: 1,
      count_sounds_with_tag: 2,
      tag_selected?: 2
    ]

  import FileFilter, only: [filter_files: 3]

  @presence_topic "soundboard:presence"
  @pubsub_topic "soundboard"

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Soundboard.PubSub, @pubsub_topic)
      send(self(), :load_sound_files)
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
    |> assign(:upload_name, "")
    |> assign(:upload_tags, [])
    |> assign(:upload_tag_input, "")
    |> assign(:upload_tag_suggestions, [])
    |> assign(:upload_ready, false)
    |> assign(:show_delete_confirm, false)
    |> assign(:selected_tags, [])
    |> assign(:is_join_sound, false)
    |> assign(:is_leave_sound, false)
    |> allow_upload(:audio,
      accept: ~w(audio/mpeg audio/wav audio/ogg audio/x-m4a),
      max_entries: 1,
      max_file_size: 25_000_000
    )
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("save", %{"name" => custom_name}, socket) do
    case UploadHandler.handle_upload(
           socket,
           %{"name" => custom_name},
           &handle_uploaded_entries/3
         ) do
      {:ok, socket} -> {:noreply, load_sound_files(socket)}
      {:error, socket} -> {:noreply, socket}
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
  def handle_event("edit", %{"name" => filename}, socket) do
    sound =
      case Repo.get_by(Sound, filename: filename) do
        nil -> %Sound{filename: filename, tags: [], user_id: socket.assigns.current_user.id}
        sound ->
          sound
          |> Repo.preload(:tags)
          |> Map.put(:is_join_sound, !!sound.is_join_sound)
          |> Map.put(:is_leave_sound, !!sound.is_leave_sound)
      end

    {:noreply,
     socket
     |> assign(:current_sound, sound)
     |> assign(:show_modal, true)
     |> assign(:tag_input, "")
     |> assign(:tag_suggestions, [])}
  end

  @impl true
  def handle_event("save_upload", params, socket) do
    Logger.info("Saving upload with params: #{inspect(params)}")

    params = Map.merge(params, %{
      "is_join_sound" => socket.assigns.is_join_sound,
      "is_leave_sound" => socket.assigns.is_leave_sound
    })

    case SoundboardWeb.Live.UploadHandler.handle_upload(socket, params, &handle_uploaded_entries/3) do
      {:ok, socket} ->
        {:noreply,
         socket
         |> assign(:show_upload_modal, false)
         |> assign(:upload_tags, [])
         |> assign(:upload_name, "")
         |> assign(:upload_tag_input, "")
         |> assign(:upload_tag_suggestions, [])
         |> assign(:is_join_sound, false)
         |> assign(:is_leave_sound, false)
         |> load_sound_files()
         |> put_flash(:info, "File uploaded successfully")}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_upload", params, socket) do
    Logger.info("Validating upload with params: #{inspect(params)}")

    # Validate the uploaded file
    changeset =
      case SoundboardWeb.Live.UploadHandler.validate_upload(socket) do
        {:ok, _socket} ->
          # File is valid
          Ecto.Changeset.change(%Soundboard.Sound{})
        {:error, _socket} ->
          # Create an error changeset
          data = %Soundboard.Sound{}
          types = %{file: :string}
          {data, types}
          |> Ecto.Changeset.cast(%{}, [:file])
          |> Ecto.Changeset.add_error(:file, "Please select a file")
      end

    # Validate the form data
    changeset =
      changeset
      |> Ecto.Changeset.cast(params, [:is_join_sound, :is_leave_sound])
      |> validate_sound_settings(params)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:upload_name, params["name"] || "")}
  end

  defp validate_sound_settings(changeset, _params) do
    changeset
  end

  defp handle_uploaded_entries(socket, name, func) do
    Phoenix.LiveView.consume_uploaded_entries(socket, name, func)
  end

  @impl true
  def handle_event("show_upload_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_upload_modal, true)
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
    sound = socket.assigns.current_sound
    user_id = socket.assigns.current_user.id

    # Reset any existing join sound if setting a new one
    if params["is_join_sound"] == "true" do
      query = from(s in Sound,
        where: [user_id: ^user_id, is_join_sound: true],
        where: s.id != ^sound.id  # Don't reset the current sound
      )
      Repo.update_all(query, set: [is_join_sound: false])
    end

    # Reset any existing leave sound if setting a new one
    if params["is_leave_sound"] == "true" do
      query = from(s in Sound,
        where: [user_id: ^user_id, is_leave_sound: true],
        where: s.id != ^sound.id  # Don't reset the current sound
      )
      Repo.update_all(query, set: [is_leave_sound: false])
    end

    case sound
         |> Sound.changeset(%{
           filename: params["filename"] <> Path.extname(sound.filename),
           user_id: user_id,
           is_join_sound: params["is_join_sound"] == "true",
           is_leave_sound: params["is_leave_sound"] == "true"
         })
         |> Repo.update() do
      {:ok, _updated_sound} ->
        {:noreply,
         socket
         |> assign(:show_modal, false)
         |> assign(:current_sound, nil)
         |> load_sound_files()
         |> put_flash(:info, "Sound updated successfully")}

      {:error, %Ecto.Changeset{errors: [filename: {_, [constraint: :unique, constraint_name: _]}]}} ->
        {:noreply,
         socket
         |> put_flash(:error, "A sound with that name already exists")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error updating sound")}
    end
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
    case FileHandler.delete_file(socket) do
      {:ok, message} ->
        {:noreply,
         socket
         |> assign(:show_delete_confirm, false)
         |> assign(:show_modal, false)
         |> assign(:current_sound, nil)
         |> load_sound_files()
         |> put_flash(:info, message)}

      {:error, message} ->
        {:noreply,
         socket
         |> put_flash(:error, message)}
    end
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
    # Reload the uploaded files list
    uploaded_files = Soundboard.Sound.with_tags() |> Soundboard.Repo.all()
    {:noreply, assign(socket, :uploaded_files, uploaded_files)}
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

  defp assign_upload_name(socket, %{"name" => name}), do: assign(socket, :upload_name, name)
  defp assign_upload_name(socket, _params), do: socket

  defp load_sound_files(socket) do
    assign(socket, :uploaded_files, FileHandler.load_sound_files())
  end

  defp clear_flash_after_timeout(socket) do
    Process.send_after(self(), :clear_flash, 3000)
    socket
  end

  @impl true
  def handle_event("toggle_join_sound", _params, socket) do
    {:noreply, assign(socket, :is_join_sound, !socket.assigns.is_join_sound)}
  end

  @impl true
  def handle_event("toggle_leave_sound", _params, socket) do
    {:noreply, assign(socket, :is_leave_sound, !socket.assigns.is_leave_sound)}
  end
end
