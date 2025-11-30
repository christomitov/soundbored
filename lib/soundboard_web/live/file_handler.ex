defmodule SoundboardWeb.Live.FileHandler do
  @moduledoc """
  Handles the renaming and deletion of files.
  """

  alias Ecto.Multi
  alias Phoenix.PubSub
  alias Soundboard.Accounts.Tenants
  alias Soundboard.PubSubTopics
  alias Soundboard.{Repo, Sound}
  import Ecto.Query

  require Logger

  @upload_directory "priv/static/uploads"

  def rename_file(old_name, new_name, socket) do
    if String.trim(new_name) == "" do
      {:ok, "No changes made"}
    else
      new_name = String.trim(new_name) <> Path.extname(old_name)
      perform_rename(old_name, new_name, socket)
    end
  end

  defp perform_rename(old_name, new_name, socket) do
    old_path = Path.join(@upload_directory, old_name)
    new_path = Path.join(@upload_directory, new_name)

    cond do
      old_name == new_name -> {:ok, "No changes made"}
      File.exists?(new_path) -> {:error, "A file with that name already exists"}
      true -> execute_rename(old_path, new_path, socket, new_name)
    end
  end

  defp execute_rename(old_path, new_path, socket, new_name) do
    Repo.transaction(fn ->
      with :ok <- File.rename(old_path, new_path),
           {:ok, _updated_sound} <- update_sound_filename(socket.assigns.current_sound, new_name) do
        broadcast_update(tenant_from_socket(socket))
        {:ok, "File renamed successfully!"}
      else
        error ->
          File.rename(new_path, old_path)
          Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _} -> {:error, "Failed to rename file"}
    end
  end

  def delete_file(socket) do
    sound = socket.assigns.current_sound

    case sound.source_type do
      "url" ->
        # For URL sounds, just delete the database record
        case Repo.delete(sound) do
          {:ok, _} ->
            broadcast_update(tenant_from_socket(socket))
            {:ok, "Sound deleted successfully!"}

          {:error, _} ->
            {:error, "Failed to delete sound"}
        end

      "local" ->
        # For local sounds, delete both file and database record
        file_path = Path.join(@upload_directory, sound.filename)

        with :ok <- File.rm(file_path),
             {:ok, _} <- maybe_delete_record(sound) do
          broadcast_update(sound.tenant_id)
          {:ok, "Sound deleted successfully!"}
        else
          _ -> {:error, "Failed to delete sound"}
        end
    end
  end

  def load_sound_files do
    case File.ls(@upload_directory) do
      {:ok, files} ->
        files
        |> Enum.filter(&valid_audio_file?/1)
        |> Enum.map(fn filename ->
          sound =
            Repo.get_by(Sound, filename: filename) ||
              Repo.insert!(%Sound{filename: filename})

          Repo.preload(sound, :tags)
        end)
        |> Enum.sort_by(& &1.filename)

      {:error, _} ->
        []
    end
  end

  def save_upload(socket, custom_name, uploaded_entries_fn) do
    if Enum.empty?(socket.assigns.uploads.audio.entries) do
      {:error, "Please select a file to upload"}
    else
      process_upload(socket, custom_name, uploaded_entries_fn)
    end
  end

  defp process_upload(socket, custom_name, uploaded_entries_fn) do
    results = handle_file_copy(socket, custom_name, uploaded_entries_fn)

    case results do
      [filename] -> {:ok, filename}
      [{:ok, filename}] -> {:ok, filename}
      _ -> {:error, "Error saving file"}
    end
  end

  defp handle_file_copy(socket, custom_name, uploaded_entries_fn) do
    uploaded_entries_fn.(socket, :audio, fn %{path: path}, entry ->
      filename = custom_name <> Path.extname(entry.client_name)
      dest = Path.join(@upload_directory, filename)
      File.mkdir_p!(Path.dirname(dest))

      case File.cp(path, dest) do
        :ok ->
          Logger.info("File saved successfully to #{dest}")
          {:ok, filename}

        {:error, reason} ->
          Logger.error("Failed to save file: #{inspect(reason)}")
          {:postpone, reason}
      end
    end)
  end

  defp update_sound_filename(sound, new_name) do
    old_name = sound.filename

    Multi.new()
    |> Multi.update(:sound, Sound.changeset(sound, %{filename: new_name}))
    |> Multi.update_all(
      :plays,
      from(p in Soundboard.Stats.Play,
        where: p.sound_name == ^old_name and p.tenant_id == ^sound.tenant_id
      ),
      set: [sound_name: new_name]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{sound: updated_sound}} -> {:ok, updated_sound}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  defp maybe_delete_record(nil), do: {:ok, nil}
  defp maybe_delete_record(sound), do: Repo.delete(sound)

  defp valid_audio_file?(filename) do
    extension = Path.extname(filename)
    extension in ~w(.mp3 .wav .ogg .m4a)
  end

  defp broadcast_update(tenant_id) do
    message = {:files_updated, tenant_id}
    PubSub.broadcast(Soundboard.PubSub, PubSubTopics.soundboard_topic(tenant_id), message)
  end

  defp tenant_from_socket(%{assigns: %{current_tenant: %{id: id}}}), do: id

  defp tenant_from_socket(%{assigns: %{current_sound: %{tenant_id: id}}}), do: id

  defp tenant_from_socket(_), do: Tenants.ensure_default_tenant!().id
end
