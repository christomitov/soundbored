defmodule Soundboard.Sounds.Uploads.Source do
  @moduledoc false

  import Ecto.Changeset
  import Ecto.Query

  require Logger

  alias Soundboard.{Repo, Sound, UploadsPath}

  @allowed_extensions ~w(.mp3 .wav .ogg .m4a)

  @spec prepare(map(), :validate | :create) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def prepare(%{source_type: "url"} = params, _mode) do
    with {:ok, url} <- validate_url(params.url),
         filename <- params.name <> url_file_extension(url),
         :ok <- validate_destination_filename(filename) do
      {:ok,
       %{
         filename: filename,
         source_type: "url",
         url: url,
         copied_file_path: nil
       }}
    end
  end

  def prepare(%{source_type: "local"} = params, :validate) do
    with {:ok, upload} <- validate_local_upload(params.upload, :validate),
         {:ok, ext} <- validate_local_extension(upload.filename),
         filename <- params.name <> ext,
         :ok <- validate_destination_filename(filename) do
      {:ok,
       %{
         filename: filename,
         source_type: "local",
         url: nil,
         copied_file_path: nil
       }}
    end
  end

  def prepare(%{source_type: "local"} = params, :create) do
    with {:ok, upload} <- validate_local_upload(params.upload, :create),
         {:ok, ext} <- validate_local_extension(upload.filename),
         filename <- params.name <> ext,
         :ok <- validate_destination_filename(filename),
         {:ok, copied_file_path} <- copy_local_file(upload.path, filename) do
      {:ok,
       %{
         filename: filename,
         source_type: "local",
         url: nil,
         copied_file_path: copied_file_path
       }}
    end
  end

  def prepare(_params, _mode) do
    {:error, add_error(change(%Sound{}), :source_type, "must be either 'local' or 'url'")}
  end

  @spec cleanup_local_file(String.t() | nil) :: :ok
  def cleanup_local_file(path) when is_binary(path) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to clean up copied upload #{path}: #{inspect(reason)}")
        :ok
    end
  end

  def cleanup_local_file(_path), do: :ok

  defp validate_url(url) when is_binary(url) do
    if blank?(url) do
      {:error, add_error(change(%Sound{}), :url, "can't be blank")}
    else
      {:ok, url}
    end
  end

  defp validate_url(_url), do: {:error, add_error(change(%Sound{}), :url, "can't be blank")}

  defp validate_local_upload(nil, _mode),
    do: {:error, add_error(change(%Sound{}), :file, "Please select a file")}

  defp validate_local_upload(%{filename: filename} = upload, :validate) do
    if blank?(filename) do
      {:error, add_error(change(%Sound{}), :file, "Please select a file")}
    else
      {:ok, %{path: Map.get(upload, :path), filename: filename}}
    end
  end

  defp validate_local_upload(%{path: path, filename: filename}, :create) when is_binary(path) do
    if blank?(filename) do
      {:error, add_error(change(%Sound{}), :file, "Invalid file upload")}
    else
      {:ok, %{path: path, filename: filename}}
    end
  end

  defp validate_local_upload(_, _mode),
    do: {:error, add_error(change(%Sound{}), :file, "Please select a file")}

  defp validate_local_extension(filename) do
    ext = filename |> Path.extname() |> String.downcase()

    if ext in @allowed_extensions do
      {:ok, ext}
    else
      {:error,
       add_error(
         change(%Sound{}),
         :file,
         "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."
       )}
    end
  end

  defp copy_local_file(src_path, filename) do
    uploads_dir = UploadsPath.dir()
    dest_path = UploadsPath.file_path(filename)

    with :ok <- ensure_uploads_dir(uploads_dir),
         :ok <- File.cp(src_path, dest_path) do
      {:ok, dest_path}
    else
      {:error, _reason} ->
        {:error, add_error(change(%Sound{}), :file, "Error saving file")}
    end
  end

  defp ensure_uploads_dir(uploads_dir) do
    case File.mkdir_p(uploads_dir) do
      :ok -> :ok
      {:error, _reason} -> {:error, add_error(change(%Sound{}), :file, "Error saving file")}
    end
  end

  defp validate_destination_filename(filename) do
    dest_path = UploadsPath.file_path(filename)

    if filename_taken?(filename) or File.exists?(dest_path) do
      {:error, add_error(change(%Sound{}), :filename, "has already been taken")}
    else
      :ok
    end
  end

  defp filename_taken?(filename) do
    from(s in Sound, where: s.filename == ^filename)
    |> Repo.exists?()
  end

  defp url_file_extension(url) when is_binary(url) do
    ext =
      url
      |> URI.parse()
      |> Map.get(:path)
      |> case do
        nil -> ""
        path -> String.downcase(Path.extname(path || ""))
      end

    if ext in @allowed_extensions, do: ext, else: ""
  end

  defp url_file_extension(_), do: ""

  defp blank?(value), do: value in [nil, ""]
end
