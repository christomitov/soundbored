defmodule SoundboardWeb.Live.UploadHandler do
  @moduledoc """
  Handles LiveView upload validation and delegates creation to the shared upload service.
  """

  import Ecto.Changeset

  alias Soundboard.Sound
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
        {:error, error_changeset(:source_type, "must be either 'local' or 'url'"), socket}
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
      {:error, reason} -> {:error, reason, socket}
    end
  end

  defp handle_local_upload(socket, params, consume_uploaded_entries_fn) do
    results =
      consume_uploaded_entries_fn.(socket, :audio, fn meta, entry ->
        consume_local_entry(socket, params, meta, entry)
      end)

    handle_local_upload_result(results, socket)
  end

  defp consume_local_entry(socket, params, %{path: path}, entry) do
    create_params =
      Map.merge(base_upload_params(socket, params), %{
        source_type: "local",
        upload: %{path: path, filename: entry.client_name}
      })

    {:ok, Uploads.create(create_params)}
  end

  defp handle_local_upload_result([{:ok, {:ok, sound}}], _socket), do: {:ok, sound}

  defp handle_local_upload_result([{:ok, {:error, reason}}], socket),
    do: {:error, reason, socket}

  defp handle_local_upload_result([], socket),
    do: {:error, error_changeset(:file, "Please select a file"), socket}

  defp handle_local_upload_result(_results, socket),
    do: {:error, error_changeset(:file, "Error saving file"), socket}

  defp base_upload_params(socket, params) do
    Uploads.build_create_request(params, socket.assigns.current_user, %{
      tags: socket.assigns.upload_tags,
      default_volume_percent: socket.assigns[:upload_volume] || 100
    })
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
        if Sound.filename_conflicts_across_extensions?(name, Uploads.allowed_extensions()) do
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

  defp validate_name_unique(changeset) do
    case get_field(changeset, :filename) do
      nil ->
        changeset

      filename ->
        if Sound.filename_taken?(filename) do
          add_error(changeset, :filename, "has already been taken")
        else
          changeset
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

  defp error_changeset(field, message) do
    add_error(change(%Sound{}), field, message)
  end
end
