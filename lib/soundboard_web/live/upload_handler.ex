defmodule SoundboardWeb.Live.UploadHandler do
  alias SoundboardWeb.Live.FileHandler
  alias Soundboard.{Sound, Repo}
  import Ecto.Query
  import Ecto.Changeset
  require Logger

  def validate_upload(socket, params) do
    # Create a changeset for validation
    changeset =
      %Sound{}
      |> Sound.changeset(%{
        filename: (params["name"] || "") <> get_file_extension(socket),
        user_id: socket.assigns.current_user.id
      })
      |> validate_name_unique()
      |> validate_file_selected(socket)

    if changeset.valid? do
      {:ok, socket}
    else
      {:error, changeset}
    end
  end

  def handle_upload(socket, %{"name" => custom_name} = params, uploaded_entries_fn) do
    case validate_upload(socket, params) do
      {:ok, _socket} ->
        do_handle_upload(socket, custom_name, params, uploaded_entries_fn)

      {:error, changeset} ->
        {:error, get_error_message(changeset), socket}
    end
  end

  defp do_handle_upload(socket, custom_name, params, uploaded_entries_fn) do
    user_id = socket.assigns.current_user.id

    # First try to save the file
    case FileHandler.save_upload(socket, custom_name, uploaded_entries_fn) do
      {:ok, filename} ->
        # Create sound params with proper boolean conversion and tags
        sound_params = %{
          filename: filename,
          user_id: user_id,
          is_join_sound: params["is_join_sound"] in ["on", "true", true],
          is_leave_sound: params["is_leave_sound"] in ["on", "true", true]
        }

        # Wrap the entire database operation in a transaction
        case Repo.transaction(fn ->
               try do
                 # First unset any existing join/leave sounds
                 if sound_params.is_join_sound do
                   from(s in Sound, where: [user_id: ^user_id, is_join_sound: true])
                   |> Repo.update_all(set: [is_join_sound: false])
                 end

                 if sound_params.is_leave_sound do
                   from(s in Sound, where: [user_id: ^user_id, is_leave_sound: true])
                   |> Repo.update_all(set: [is_leave_sound: false])
                 end

                 # Then create the new sound
                 case %Sound{}
                      |> Sound.changeset(sound_params)
                      |> Repo.insert() do
                   {:ok, sound} ->
                     # Add tags after sound is created
                     tags = socket.assigns.upload_tags || []

                     Repo.preload(sound, :tags)
                     |> Sound.changeset(%{tags: tags})
                     |> Repo.update!()

                   {:error, changeset} ->
                     Repo.rollback({:insert_error, changeset})
                 end
               rescue
                 e ->
                   Logger.error("Error in transaction: #{inspect(e)}")
                   Repo.rollback({:exception, e})
               end
             end) do
          {:ok, _sound} ->
            # Broadcast updates
            Phoenix.PubSub.broadcast(Soundboard.PubSub, "uploads", {:sound_uploaded})
            Phoenix.PubSub.broadcast(Soundboard.PubSub, "stats", {:stats_updated})
            :ok

          {:error, {:insert_error, changeset}} ->
            Logger.error("Error creating sound: #{inspect(changeset)}")
            {:error, "Error saving sound", socket}

          {:error, {:exception, e}} ->
            Logger.error("Exception while saving sound: #{inspect(e)}")
            {:error, "An unexpected error occurred", socket}
        end

      {:error, message} ->
        Logger.error("Error saving upload: #{message}")
        {:error, message, socket}
    end
  end

  defp validate_name_unique(changeset) do
    case get_field(changeset, :filename) do
      nil -> changeset
      filename ->
        case Repo.get_by(Sound, filename: filename) do
          nil -> changeset
          _sound -> add_error(changeset, :filename, "has already been taken")
        end
    end
  end

  defp validate_file_selected(changeset, socket) do
    case Phoenix.LiveView.uploaded_entries(socket, :audio) do
      {[], []} -> add_error(changeset, :file, "Please select a file")
      _ -> changeset
    end
  end

  defp get_file_extension(socket) do
    case Phoenix.LiveView.uploaded_entries(socket, :audio) do
      {[entry | _], _} -> Path.extname(entry.client_name)
      {_, [entry | _]} -> Path.extname(entry.client_name)
      _ -> ""
    end
  end

  defp get_error_message(changeset) do
    Enum.map(changeset.errors, fn
      {:filename, {"has already been taken", _}} -> "A sound with that name already exists"
      {:file, {"Please select a file", _}} -> "Please select a file"
      {_key, {msg, _}} -> msg
    end)
    |> Enum.join(", ")
  end
end
