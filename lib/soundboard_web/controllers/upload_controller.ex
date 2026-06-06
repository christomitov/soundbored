defmodule SoundboardWeb.UploadController do
  use SoundboardWeb, :controller

  alias Soundboard.UploadsPath

  @allowed_extensions ~w(.mp3 .wav .ogg .m4a .flac .png .jpg .jpeg .webp)

  def show(conn, %{"path" => path}) do
    with {:ok, file_path} <- UploadsPath.safe_joined_path(path),
         true <- File.regular?(file_path),
         true <- String.downcase(Path.extname(file_path)) in @allowed_extensions do
      conn
      |> put_resp_content_type(MIME.from_path(file_path), nil)
      |> send_file(200, file_path)
    else
      _ -> send_resp(conn, 404, "File not found")
    end
  end
end
