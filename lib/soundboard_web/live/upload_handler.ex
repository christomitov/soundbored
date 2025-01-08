defmodule SoundboardWeb.Live.UploadHandler do
  alias SoundboardWeb.Live.FileHandler

  def handle_upload(socket, %{"name" => custom_name}, uploaded_entries_fn) do
    case FileHandler.save_upload(socket, custom_name, uploaded_entries_fn) do
      {:ok, filename} ->
        # Create sound record with user association
        {:ok, _sound} =
          Soundboard.Sound.changeset(%Soundboard.Sound{}, %{
            filename: filename,
            user_id: socket.assigns.current_user.id
          })
          |> Soundboard.Repo.insert()

        {:ok,
         socket
         |> Phoenix.LiveView.put_flash(:info, "File uploaded successfully")}

      {:error, message} ->
        {:error,
         socket
         |> Phoenix.LiveView.put_flash(:error, message)}
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
