defmodule SoundboardWeb.Live.UploadHandler do
  @moduledoc """
  Handles the upload of sounds from a local file or a URL.
  """
  alias SoundboardWeb.Live.FileHandler
  alias Soundboard.{Repo, Sound}
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
        filename: name <> url_file_extension(url),
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
    case {name, get_file_extension(socket)} do
      {n, _} when is_nil(n) or n == "" ->
        case Phoenix.LiveView.uploaded_entries(socket, :audio) do
          {[], []} -> {:error, add_error(%Ecto.Changeset{}, :file, "Please select a file")}
          _ -> {:ok, socket}
        end

      {_, ""} ->
        if name_conflicts_across_exts?(name) do
          {:error, add_error(%Ecto.Changeset{}, :filename, "has already been taken")}
        else
          {:ok, socket}
        end

      {_, ext} ->
        changeset =
          %Sound{}
          |> Sound.changeset(%{
            filename: name <> ext,
            user_id: socket.assigns.current_user.id
          })
          |> validate_name_unique()

        if changeset.valid? do
          {:ok, socket}
        else
          {:error, changeset}
        end
    end
  end

  defp name_conflicts_across_exts?(base) do
    exts = [".mp3", ".wav", ".ogg", ".m4a"]
    names = Enum.map(exts, &("#{base}" <> &1))

    from(s in Sound, where: s.filename in ^names)
    |> Repo.exists?()
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
      filename: params["name"] <> url_file_extension(params["url"]),
      url: params["url"],
      source_type: "url",
      user_id: user_id,
      join_leave_user_id:
        if params["is_join_sound"] == "true" || params["is_leave_sound"] == "true" do
          user_id
        end,
      is_join_sound: params["is_join_sound"] == "true",
      is_leave_sound: params["is_leave_sound"] == "true"
    }

    handle_sound_transaction(sound_params, user_id, socket)
  end

  defp handle_local_upload(socket, params, user_id, consume_uploaded_entries_fn) do
    case FileHandler.save_upload(socket, params["name"], consume_uploaded_entries_fn) do
      {:ok, filename} ->
        sound_params = %{
          filename: filename,
          source_type: "local",
          user_id: user_id,
          join_leave_user_id:
            if params["is_join_sound"] == "true" || params["is_leave_sound"] == "true" do
              user_id
            end,
          is_join_sound: params["is_join_sound"] == "true",
          is_leave_sound: params["is_leave_sound"] == "true"
        }

        handle_sound_transaction(sound_params, user_id, socket)

      {:error, message} ->
        {:error, message, socket}
    end
  end

  defp handle_sound_transaction(sound_params, user_id, socket) do
    Repo.transaction(fn ->
      clear_existing_settings(user_id, sound_params)
      create_sound_with_settings(sound_params, user_id, socket)
    end)
    |> case do
      {:ok, {:ok, sound}} -> {:ok, sound}
      {:ok, {:error, changeset}} -> {:error, get_error_message(changeset), socket}
      {:error, changeset} -> {:error, get_error_message(changeset), socket}
    end
  end

  defp clear_existing_settings(user_id, %{is_join_sound: true}) do
    from(s in Sound, where: s.join_leave_user_id == ^user_id and s.is_join_sound == true)
    |> Repo.update_all(set: [is_join_sound: false, join_leave_user_id: nil])
  end

  defp clear_existing_settings(user_id, %{is_leave_sound: true}) do
    from(s in Sound, where: s.join_leave_user_id == ^user_id and s.is_leave_sound == true)
    |> Repo.update_all(set: [is_leave_sound: false, join_leave_user_id: nil])
  end

  defp clear_existing_settings(_, _), do: nil

  defp create_sound_with_settings(sound_params, user_id, socket) do
    with {:ok, sound} <- create_sound(sound_params, socket.assigns.upload_tags),
         {:ok, _setting} <- create_user_setting(sound, user_id, sound_params) do
      broadcast_updates()
      {:ok, sound}
    end
  end

  defp create_user_setting(sound, user_id, sound_params) do
    %Soundboard.UserSoundSetting{
      user_id: user_id,
      sound_id: sound.id,
      is_join_sound: sound_params.is_join_sound,
      is_leave_sound: sound_params.is_leave_sound
    }
    |> Repo.insert()
  end

  defp broadcast_updates do
    Phoenix.PubSub.broadcast(Soundboard.PubSub, "uploads", {:sound_uploaded})
    Phoenix.PubSub.broadcast(Soundboard.PubSub, "stats", {:stats_updated})
  end

  defp create_sound(params, tags) do
    case %Sound{} |> Sound.changeset(params) |> Repo.insert() do
      {:ok, sound} ->
        case insert_sound_tags(sound, tags) do
          {:ok, _} -> {:ok, sound}
          error -> error
        end

      error ->
        error
    end
  end

  defp insert_sound_tags(_sound, []), do: {:ok, nil}

  defp insert_sound_tags(sound, tags) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    tag_entries =
      Enum.map(tags, fn tag ->
        %{
          sound_id: sound.id,
          tag_id: tag.id,
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all("sound_tags", tag_entries) do
      {n, _} when n > 0 -> {:ok, sound}
      _ -> {:error, "Failed to insert tags"}
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

  defp get_file_extension(socket) do
    case Phoenix.LiveView.uploaded_entries(socket, :audio) do
      {[entry | _], _} -> Path.extname(entry.client_name)
      {_, [entry | _]} -> Path.extname(entry.client_name)
      _ -> ""
    end
  end

  # Extract a safe extension from a URL's path. Only returns extensions
  # we support for playback; returns "" if none or unsupported.
  defp url_file_extension(url) when is_binary(url) do
    ext =
      url
      |> URI.parse()
      |> Map.get(:path)
      |> case do
        nil -> ""
        path -> String.downcase(Path.extname(path || ""))
      end

    case ext do
      ".mp3" -> ".mp3"
      ".wav" -> ".wav"
      ".ogg" -> ".ogg"
      ".m4a" -> ".m4a"
      _ -> ""
    end
  end

  defp url_file_extension(_), do: ""

  defp get_error_message(changeset) when is_map(changeset) do
    Enum.map_join(changeset.errors, ", ", fn
      {:filename, {"has already been taken", _}} -> "A sound with that name already exists"
      {:file, {"Please select a file", _}} -> "Please select a file"
      {key, {msg, _}} -> "#{key} #{msg}"
    end)
  end

  defp get_error_message(error) when is_binary(error), do: error
  defp get_error_message(_), do: "An unexpected error occurred"
end
