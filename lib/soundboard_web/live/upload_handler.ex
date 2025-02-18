defmodule SoundboardWeb.Live.UploadHandler do
  alias SoundboardWeb.Live.FileHandler
  alias Soundboard.{Sound, Repo}
  import Ecto.Query
  import Ecto.Changeset
  require Logger

  def validate_upload(socket, params) do
    source_type = params["source_type"] || "local"
    name = params["name"]
    url = params["url"]

    cond do
      source_type == "url" and (is_nil(url) or url == "") and (is_nil(name) or name == "") ->
        {:ok, socket}

      source_type == "url" ->
        validate_url_upload(socket, name, url)

      true ->
        validate_local_upload(socket, name)
    end
  end

  defp validate_url_upload(socket, name, url) do
    changeset =
      %Sound{}
      |> Sound.changeset(%{
        filename: name <> ".mp3",
        url: url,
        source_type: "url"
      })
      |> validate_name_unique()

    if changeset.valid? do
      {:ok, socket}
    else
      {:error, changeset}
    end
  end

  defp validate_local_upload(socket, name) do
    changeset =
      %Sound{}
      |> Sound.changeset(%{
        filename: (name || "") <> get_file_extension(socket),
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

  def handle_upload(socket, params, consume_uploaded_entries_fn) do
    user_id = socket.assigns.current_user.id
    source_type = params["source_type"] || "local"

    case source_type do
      "url" ->
        handle_url_upload(socket, params, user_id)

      "local" ->
        handle_local_upload(socket, params, user_id, consume_uploaded_entries_fn)
    end
  end

  defp handle_url_upload(socket, params, user_id) do
    sound_params = %{
      filename: params["name"] <> ".mp3",
      url: params["url"],
      source_type: "url",
      user_id: user_id,
      is_join_sound: params["is_join_sound"] == "true",
      is_leave_sound: params["is_leave_sound"] == "true"
    }

    # Handle join/leave sound resets in a transaction
    Repo.transaction(fn ->
      # Only reset the user's own join/leave sounds
      if sound_params.is_join_sound do
        # Add user_id check to only reset own sounds
        from(s in Sound,
          where: s.user_id == ^user_id and s.is_join_sound == true
        )
        |> Repo.update_all(set: [is_join_sound: false])
      end

      if sound_params.is_leave_sound do
        # Add user_id check to only reset own sounds
        from(s in Sound,
          where: s.user_id == ^user_id and s.is_leave_sound == true
        )
        |> Repo.update_all(set: [is_leave_sound: false])
      end

      # Verify ownership before creating sound
      case create_sound_with_ownership_check(sound_params, socket.assigns.upload_tags, user_id) do
        {:ok, sound} ->
          Phoenix.PubSub.broadcast(Soundboard.PubSub, "uploads", {:sound_uploaded})
          Phoenix.PubSub.broadcast(Soundboard.PubSub, "stats", {:stats_updated})
          sound

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, _sound} -> :ok
      {:error, changeset} -> {:error, get_error_message(changeset), socket}
    end
  end

  defp handle_local_upload(socket, params, user_id, consume_uploaded_entries_fn) do
    case FileHandler.save_upload(socket, params["name"], consume_uploaded_entries_fn) do
      {:ok, filename} ->
        sound_params = %{
          filename: filename,
          source_type: "local",
          user_id: user_id,
          is_join_sound: params["is_join_sound"] == "true",
          is_leave_sound: params["is_leave_sound"] == "true"
        }

        # Use the same transaction pattern for local uploads
        Repo.transaction(fn ->
          # Only reset the user's own join/leave sounds
          if sound_params.is_join_sound do
            from(s in Sound,
              where: s.user_id == ^user_id and s.is_join_sound == true
            )
            |> Repo.update_all(set: [is_join_sound: false])
          end

          if sound_params.is_leave_sound do
            from(s in Sound,
              where: s.user_id == ^user_id and s.is_leave_sound == true
            )
            |> Repo.update_all(set: [is_leave_sound: false])
          end

          case create_sound_with_ownership_check(
                 sound_params,
                 socket.assigns.upload_tags,
                 user_id
               ) do
            {:ok, sound} ->
              Phoenix.PubSub.broadcast(Soundboard.PubSub, "uploads", {:sound_uploaded})
              Phoenix.PubSub.broadcast(Soundboard.PubSub, "stats", {:stats_updated})
              sound

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
        |> case do
          {:ok, _sound} -> :ok
          {:error, changeset} -> {:error, get_error_message(changeset), socket}
        end

      {:error, message} ->
        {:error, message, socket}
    end
  end

  # New helper function to verify ownership
  defp create_sound_with_ownership_check(params, tags, user_id) do
    if params.user_id == user_id do
      %Sound{}
      |> Sound.changeset(Map.put(params, :tags, tags))
      |> Repo.insert()
    else
      {:error, "Unauthorized to set sounds for other users"}
    end
  end

  defp validate_name_unique(changeset) do
    case get_field(changeset, :filename) do
      nil ->
        changeset

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
