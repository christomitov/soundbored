defmodule SoundboardWeb.VideoSessionController do
  use SoundboardWeb, :controller

  alias Soundboard.Video.SessionsPath

  @allowed_extensions ~w(.m3u8 .ts .m4s .mp4 .aac .vtt)

  def show(conn, %{"session_id" => session_id, "path" => path}) do
    with {:ok, file_path} <- SessionsPath.safe_joined_path(session_id, path),
         true <- File.regular?(file_path),
         true <- allowed_extension?(file_path) do
      conn
      |> put_resp_content_type(content_type(file_path))
      |> put_resp_header("cache-control", "no-cache")
      |> send_file(200, file_path)
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

  defp content_type(file_path) do
    case String.downcase(Path.extname(file_path)) do
      ".m3u8" -> "application/vnd.apple.mpegurl"
      ".ts" -> "video/mp2t"
      ".m4s" -> "video/iso.segment"
      ".mp4" -> "video/mp4"
      ".aac" -> "audio/aac"
      ".vtt" -> "text/vtt"
      _ -> "application/octet-stream"
    end
  end
end
