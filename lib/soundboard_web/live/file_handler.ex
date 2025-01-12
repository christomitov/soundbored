defmodule SoundboardWeb.Live.FileHandler do
  alias Soundboard.{Repo, Sound}
  alias Phoenix.PubSub

  require Logger

  @upload_directory "priv/static/uploads"

  def rename_file(old_name, new_name, socket) do
    if String.trim(new_name) == "" do
      {:ok, "No changes made"}
    else
      old_path = Path.join(@upload_directory, old_name)
      new_name = String.trim(new_name) <> Path.extname(old_name)
      new_path = Path.join(@upload_directory, new_name)

      cond do
        old_name == new_name ->
          {:ok, "No changes made"}

        File.exists?(new_path) ->
          {:error, "A file with that name already exists"}

        true ->
          perform_rename(old_path, new_path, new_name, socket)
      end
    end
  end

  def delete_file(socket) do
    sound = socket.assigns.current_sound
    file_path = Path.join(@upload_directory, sound.filename)

    with :ok <- File.rm(file_path),
         {:ok, _} <- maybe_delete_record(sound) do
      broadcast_update()
      {:ok, "Sound deleted successfully!"}
    else
      _ -> {:error, "Failed to delete sound"}
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
    if length(socket.assigns.uploads.audio.entries) > 0 do
      results =
        uploaded_entries_fn.(socket, :audio, fn %{path: path}, entry ->
          ext = Path.extname(entry.client_name)
          filename = custom_name <> ext
          dest = Path.join(@upload_directory, filename)

          # Ensure the uploads directory exists
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

      # Fix the return value handling
      case results do
        [filename] ->
          Logger.info("Upload successful: #{filename}")
          {:ok, filename}

        [{:ok, filename}] ->
          Logger.info("Upload successful: #{filename}")
          {:ok, filename}

        _ ->
          Logger.error("Upload failed: #{inspect(results)}")
          {:error, "Error saving file"}
      end
    else
      {:error, "Please select a file to upload"}
    end
  end

  defp perform_rename(old_path, new_path, new_name, socket) do
    with :ok <- File.rename(old_path, new_path),
         {:ok, _updated_sound} <- update_sound_filename(socket.assigns.current_sound, new_name) do
      broadcast_update()
      {:ok, "File renamed successfully!"}
    else
      _ -> {:error, "Failed to rename file"}
    end
  end

  defp update_sound_filename(sound, new_name) do
    sound
    |> Ecto.Changeset.change(filename: new_name)
    |> Repo.update()
  end

  defp maybe_delete_record(nil), do: {:ok, nil}
  defp maybe_delete_record(sound), do: Repo.delete(sound)

  defp valid_audio_file?(filename) do
    extension = Path.extname(filename)
    extension in ~w(.mp3 .wav .ogg .m4a)
  end

  defp broadcast_update do
    PubSub.broadcast(Soundboard.PubSub, "soundboard", {:files_updated})
  end
end
