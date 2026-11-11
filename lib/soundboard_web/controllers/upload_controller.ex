defmodule SoundboardWeb.UploadController do
  @moduledoc """
  Serves uploaded sound files to the signed-in user, for the browser's local
  preview. Only the stored file of a sound in the current soundboard is
  served; any other path, including another guild's sound, is a 404.
  """

  use SoundboardWeb, :controller

  import Ecto.Query, only: [from: 2]

  alias Soundboard.{Repo, Sound, UploadsPath}

  def show(conn, %{"path" => path}) do
    storage_key = Path.join(path)

    with true <- sound_in_guild?(storage_key, conn.assigns.current_guild_id),
         {:ok, file_path} <- UploadsPath.safe_joined_path(path),
         true <- File.regular?(file_path) do
      send_file(conn, 200, file_path)
    else
      _ -> send_resp(conn, 404, "File not found")
    end
  end

  defp sound_in_guild?(storage_key, guild_id) do
    Repo.exists?(
      from(s in Sound, where: s.storage_key == ^storage_key and s.guild_id == ^guild_id)
    )
  end
end
