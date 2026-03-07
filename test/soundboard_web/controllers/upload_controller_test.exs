defmodule SoundboardWeb.UploadControllerTest do
  use SoundboardWeb.ConnCase

  alias Soundboard.Accounts.User
  alias Soundboard.Repo

  setup %{conn: conn} do
    filename = "upload_controller_#{System.unique_integer([:positive])}.mp3"
    uploads_dir = Soundboard.UploadsPath.dir()
    file_path = Path.join(uploads_dir, filename)

    File.mkdir_p!(uploads_dir)
    File.write!(file_path, "audio")

    on_exit(fn -> File.rm(file_path) end)

    %{conn: conn, filename: filename}
  end

  test "GET /uploads/*path redirects unauthenticated users", %{conn: conn, filename: filename} do
    conn = get(conn, ~p"/uploads/#{filename}")

    assert redirected_to(conn) == "/auth/discord"
  end

  test "GET /uploads/*path serves files for authenticated users", %{
    conn: conn,
    filename: filename
  } do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "upload_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> get(~p"/uploads/#{filename}")

    assert response(conn, 200) == "audio"
  end

  test "GET /uploads/*path rejects traversal attempts", %{conn: conn} do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "upload_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> get("/uploads/../../mix.exs")

    assert response(conn, 404) == "File not found"
  end
end
