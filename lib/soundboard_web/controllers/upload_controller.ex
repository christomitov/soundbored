defmodule SoundboardWeb.UploadController do
  use SoundboardWeb, :controller

  alias Soundboard.UploadsPath

  def show(conn, %{"path" => path}) do
    case UploadsPath.safe_joined_path(path) do
      {:ok, file_path} ->
        if File.regular?(file_path) do
          send_file(conn, 200, file_path)
        else
          send_resp(conn, 404, "File not found")
        end

      :error ->
        send_resp(conn, 404, "File not found")
    end
  end
end
