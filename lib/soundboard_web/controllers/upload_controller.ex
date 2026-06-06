defmodule SoundboardWeb.UploadController do
  use SoundboardWeb, :controller

  alias Soundboard.UploadsPath

  @allowed_extensions ~w(.mp3 .wav .ogg .m4a .flac)

  def show(conn, %{"path" => path}) do
    with {:ok, file_path} <- UploadsPath.safe_joined_path(path),
         true <- File.regular?(file_path),
         true <- allowed_extension?(file_path) do
      send_file(conn, 200, file_path)
    else
      _ -> send_resp(conn, 404, "File not found")
    end
  end

  defp allowed_extension?(file_path) do
    file_path
    |> Path.extname()
    |> String.downcase()
    |> then(&Enum.member?(@allowed_extensions, &1))
  end
end
