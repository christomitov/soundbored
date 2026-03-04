defmodule SoundboardWeb.Live.UploadHandler do
  @moduledoc """
  Handles LiveView upload validation and delegates creation to the shared upload service.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias Soundboard.{Repo, Sound}
  alias Soundboard.Sounds.Uploads

  def validate_upload(socket, params) do
    params =
      params
      |> Map.put_new("source_type", Map.get(socket.assigns, :source_type, "local"))
      |> Map.put_new("name", nil)
      |> Map.put_new("url", nil)

    do_validate_upload(socket, params)
  end

  defp do_validate_upload(socket, %{"source_type" => "url", "name" => name, "url" => url}) do
    if blank?(url) and blank?(name) do
      {:ok, socket}
    else
      validate_url_upload(socket, name, url)
    end
  end

  defp do_validate_upload(socket, %{"name" => name}) do
    validate_local_upload(socket, name)
  end

  def handle_upload(socket, params, consume_uploaded_entries_fn) do
    source_type = params["source_type"] || "local"

    case source_type do
      "url" ->
        handle_url_upload(socket, params)

      "local" ->
        handle_local_upload(socket, params, consume_uploaded_entries_fn)

      _ ->
        {:error, "source_type must be either 'local' or 'url'", socket}
    end
  end

  defp handle_url_upload(socket, params) do
    params =
      Map.merge(base_upload_params(socket, params), %{
        source_type: "url",
        url: params["url"]
      })

    case Uploads.create(params) do
      {:ok, sound} -> {:ok, sound}
      {:error, reason} -> {:error, get_error_message(reason), socket}
    end
  end

  defp handle_local_upload(socket, params, consume_uploaded_entries_fn) do
    case consume_uploaded_entries_fn.(socket, :audio, fn %{path: path}, entry ->
           create_params =
             Map.merge(base_upload_params(socket, params), %{
               source_type: "local",
               upload: %{path: path, filename: entry.client_name}
             })

           case Uploads.create(create_params) do
             {:ok, sound} -> {:ok, {:ok, sound}}
             {:error, reason} -> {:ok, {:error, reason}}
           end
         end) do
      [{:ok, sound}] ->
        {:ok, sound}

      [{:error, reason}] ->
        {:error, get_error_message(reason), socket}

      [] ->
        {:error, "Please select a file", socket}

      {:error, reason} when is_binary(reason) ->
        {:error, reason, socket}

      _ ->
        {:error, "Error saving file", socket}
    end
  end

  defp base_upload_params(socket, params) do
    %{
      user: socket.assigns.current_user,
      name: params["name"],
      tags: socket.assigns.upload_tags,
      volume: Map.get(params, "volume"),
      default_volume_percent: socket.assigns[:upload_volume] || 100,
      is_join_sound: params["is_join_sound"],
      is_leave_sound: params["is_leave_sound"]
    }
  end

  defp blank?(value), do: value in [nil, ""]

  defp validate_url_upload(socket, name, url) do
    user_id = socket.assigns.current_user.id

    safe_name = name || ""

    changeset =
      %Sound{}
      |> Sound.changeset(%{
        filename: safe_name <> Uploads.url_file_extension(url),
        url: url,
        source_type: "url",
        user_id: user_id
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
    names = Enum.map(Uploads.allowed_extensions(), &("#{base}" <> &1))

    from(s in Sound, where: s.filename in ^names)
    |> Repo.exists?()
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

  defp get_error_message(%Ecto.Changeset{} = changeset) do
    Enum.map_join(changeset.errors, ", ", fn
      {:filename, {"has already been taken", _}} -> "A sound with that name already exists"
      {:file, {"Please select a file", _}} -> "Please select a file"
      {key, {msg, _}} -> "#{key} #{msg}"
    end)
  end

  defp get_error_message(error) when is_binary(error), do: error
  defp get_error_message(_), do: "An unexpected error occurred"
end
