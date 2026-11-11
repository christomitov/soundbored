defmodule SoundboardWeb.UploadControllerTest do
  @moduledoc """
  `GET /uploads/*path` serves a signed-in user the files of their current
  soundboard's sounds, and nothing else from the uploads directory.
  """

  use SoundboardWeb.ConnCase, async: false

  alias Soundboard.{Repo, Sound, Tenants, UploadsPath}

  setup %{conn: conn} do
    user = user_fixture()
    own = insert_sound_with_file!(user, Tenants.default_guild_id(), "own audio")
    other = insert_sound_with_file!(user, "other-guild", "other guild's audio")
    %{conn: sign_in(conn, user), own: own, other: other}
  end

  test "serves the file of a sound in the current soundboard", %{conn: conn, own: own} do
    assert conn |> get("/uploads/#{own.storage_key}") |> response(200) == "own audio"
  end

  test "does not serve another soundboard's sound file", %{conn: conn, other: other} do
    assert conn |> get("/uploads/#{other.storage_key}") |> response(404) == "File not found"
  end

  test "does not serve files outside the uploads dir", %{conn: conn} do
    assert conn |> get("/uploads/../../mix.exs") |> response(404) == "File not found"
  end

  defp insert_sound_with_file!(user, guild_id, contents) do
    storage_key = Ecto.UUID.generate() <> ".mp3"
    path = UploadsPath.file_path(storage_key)
    File.mkdir_p!(UploadsPath.dir())
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    %Sound{}
    |> Sound.changeset(%{
      filename: "upload-#{System.unique_integer([:positive])}.mp3",
      storage_key: storage_key,
      source_type: "local",
      user_id: user.id,
      guild_id: guild_id
    })
    |> Repo.insert!()
  end
end
