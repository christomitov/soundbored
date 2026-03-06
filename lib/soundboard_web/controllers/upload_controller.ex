defmodule SoundboardWeb.UploadController do
  use SoundboardWeb, :controller

  def show(conn, %{"path" => path}) do
    file_path = Soundboard.UploadsPath.joined_path(path)

    if File.exists?(file_path) do
      send_file(conn, 200, file_path)
    else
      send_resp(conn, 404, "File not found")
    end
  end
end
