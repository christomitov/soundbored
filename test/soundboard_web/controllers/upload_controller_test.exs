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

  test "GET /uploads/*path serves PNG images for authenticated users" do
    {:ok, user} = insert_user()

    images_dir = Path.join(Soundboard.UploadsPath.dir(), "images")
    image_filename = "test_img_#{System.unique_integer([:positive])}.png"
    image_path = Path.join(images_dir, image_filename)

    File.mkdir_p!(images_dir)
    File.write!(image_path, "png_content")
    on_exit(fn -> File.rm(image_path) end)

    conn =
      build_conn()
      |> init_test_session(%{user_id: user.id})
      |> get("/uploads/images/#{image_filename}")

    assert response(conn, 200) == "png_content"
  end

  test "GET /uploads/*path rejects disallowed file types for authenticated users" do
    {:ok, user} = insert_user()

    uploads_dir = Soundboard.UploadsPath.dir()
    bad_file = "evil_#{System.unique_integer([:positive])}.exe"
    bad_path = Path.join(uploads_dir, bad_file)

    File.write!(bad_path, "bad content")
    on_exit(fn -> File.rm(bad_path) end)

    conn =
      build_conn()
      |> init_test_session(%{user_id: user.id})
      |> get("/uploads/#{bad_file}")

    assert response(conn, 404) == "File not found"
  end

  test "GET /uploads/*path rejects traversal attempts", %{conn: conn} do
    {:ok, user} = insert_user()

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> get("/uploads/../../mix.exs")

    assert response(conn, 404) == "File not found"
  end

  defp insert_user do
    %User{}
    |> User.changeset(%{
      username: "upload_user_#{System.unique_integer([:positive])}",
      discord_id: Integer.to_string(System.unique_integer([:positive])),
      avatar: "avatar.png"
    })
    |> Repo.insert()
  end
end
