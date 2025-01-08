defmodule SoundboardWeb.UploadController do
  use SoundboardWeb, :controller

  def show(conn, %{"path" => path}) do
    # Ensure the path is safe and within uploads directory
    file_path = Path.join([Application.app_dir(:soundboard), "priv", "static", "uploads", path])

    if File.exists?(file_path) do
      send_file(conn, 200, file_path)
    else
      send_resp(conn, 404, "File not found")
    end
  end
end
