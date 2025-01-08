defmodule SoundboardWeb.Live.FileHandler do
  alias Soundboard.{Repo, Sound}
  alias Phoenix.PubSub
  import Phoenix.LiveView.Upload

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

  def save_upload(socket, custom_name, _consume_fn) do
    case uploaded_entries(socket, :audio) do
      {[_ | _] = _entries, []} ->
        consumed =
          consume_uploaded_entries(socket, :audio, fn meta, entry ->
            filename = get_filename(custom_name, entry)

            if File.exists?(Path.join(@upload_directory, filename)) do
              {:postpone, :file_exists}
            else
              dest = Path.join(@upload_directory, filename)
              File.cp!(meta.path, dest)

              # Create sound record with tags
              {:ok, _sound} =
                %Sound{}
                |> Sound.changeset(%{
                  filename: filename,
                  user_id: socket.assigns.current_user.id,
                  tags: socket.assigns.upload_tags
                })
                |> Repo.insert()

              filename
            end
          end)

        case consumed do
          [filename] when is_binary(filename) ->
            Phoenix.PubSub.broadcast(Soundboard.PubSub, "soundboard", {:files_updated})
            {:ok, "File uploaded successfully!"}

          _ ->
            {:error, "Upload failed"}
        end

      _ ->
        {:error, "No file selected"}
    end
  end

  defp get_filename(custom_name, entry) do
    if custom_name != "" do
      "#{custom_name}#{Path.extname(entry.client_name)}"
    else
      entry.client_name
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
