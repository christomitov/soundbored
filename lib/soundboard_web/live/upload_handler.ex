defmodule SoundboardWeb.Live.UploadHandler do
  alias SoundboardWeb.Live.FileHandler
  alias Soundboard.{Sound, Repo}
  import Ecto.Query
  require Logger

  def handle_upload(socket, %{"name" => custom_name} = params, uploaded_entries_fn) do
    user_id = socket.assigns.current_user.id

    if !custom_name || custom_name == "" do
      Logger.error("Name is required")
      {:error, "Name is required", socket}
    else
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
  end

  def validate_upload(socket) do
    case Phoenix.LiveView.uploaded_entries(socket, :audio) do
      {[], [_entry | _]} -> {:ok, socket}
      {entries, []} when entries != [] -> {:ok, socket}
      {[], []} -> {:error, socket}
      _ -> {:ok, socket}
    end
  end
end
