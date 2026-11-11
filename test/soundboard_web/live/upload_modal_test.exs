defmodule SoundboardWeb.UploadModalTest do
  use SoundboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Soundboard.{Accounts.User, Repo, Sound}

  setup %{conn: conn} do
    Repo.delete_all(Sound)
    Repo.delete_all(User)

    user =
      %User{}
      |> User.changeset(%{username: "uploader", discord_id: "42", avatar: "a.jpg"})
      |> Repo.insert!()

    {:ok, conn: init_test_session(conn, %{user_id: user.id}), user: user}
  end

  defp open_modal(conn) do
    {:ok, view, _html} = live(conn, "/")
    view |> element("[phx-click='show_upload_modal']") |> render_click()
    view
  end

  defp pick_file(view, name \\ "beep.mp3", type \\ "audio/mpeg") do
    audio =
      file_input(view, "#upload-form", :audio, [
        %{name: name, content: "ID3fake-mp3-bytes", type: type}
      ])

    {audio, view |> element("#upload-form") |> render_change(audio)}
  end

  defp name_input(view), do: element(view, "#upload-form input[name='name']")

  test "picking a file names the sound after it and enables the form", %{conn: conn} do
    view = open_modal(conn)
    pick_file(view)

    assert has_element?(view, "#upload-form input[name='name'][value='beep']")
    refute has_element?(view, "#upload-form input[name='name'][disabled]")
    refute has_element?(view, "#upload-form button[type='submit'][disabled]")
  end

  test "renaming after picking a file keeps the file", %{conn: conn} do
    view = open_modal(conn)
    pick_file(view)

    render_change(name_input(view), %{"name" => "renamed"})

    assert has_element?(view, "#upload-form input[name='name'][value='renamed']")
    refute has_element?(view, "#upload-form button[type='submit'][disabled]")
    refute render(view) =~ "Select a file first"
  end

  test "renaming then saving stores the file under the new name", %{conn: conn, user: user} do
    view = open_modal(conn)
    {audio, _html} = pick_file(view)

    render_change(name_input(view), %{"name" => "renamed"})
    render_upload(audio, "beep.mp3")
    view |> element("#upload-form") |> render_submit(%{"name" => "renamed"})

    sound = Repo.get_by!(Sound, filename: "renamed.mp3")
    assert sound.source_type == "local"
    assert sound.user_id == user.id
    refute has_element?(view, "#upload-form")
  end

  test "a name that is already taken shows an error and blocks saving", %{conn: conn, user: user} do
    %Sound{}
    |> Sound.changeset(%{filename: "taken.mp3", source_type: "local", user_id: user.id})
    |> Repo.insert!()

    view = open_modal(conn)
    pick_file(view)

    html = render_change(name_input(view), %{"name" => "taken"})

    assert html =~ "taken"
    assert has_element?(view, "#upload-form button[type='submit'][disabled]")
  end

  test "the picked file stays listed after renaming", %{conn: conn} do
    view = open_modal(conn)
    pick_file(view)

    render_change(name_input(view), %{"name" => "renamed"})

    assert view |> element("#upload-selected-file") |> render() =~ "beep.mp3"
    assert has_element?(view, "label", "Change file")
  end

  test "removing the picked file empties the form again", %{conn: conn} do
    view = open_modal(conn)
    pick_file(view)

    view |> element("#upload-selected-file button") |> render_click()

    refute has_element?(view, "#upload-selected-file")
    assert has_element?(view, "label", "Choose file")
    assert has_element?(view, "#upload-form input[name='name'][disabled]")
    assert has_element?(view, "#upload-form button[type='submit'][disabled]")
  end

  test "the volume preview points at the real file input", %{conn: conn} do
    view = open_modal(conn)
    pick_file(view)

    [file_id] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#upload-form input[type='file']")
      |> LazyHTML.attribute("id")

    assert has_element?(view, "#upload-volume-control[data-file-input-id='#{file_id}']")
  end

  test "the name stays disabled until a file is picked", %{conn: conn} do
    view = open_modal(conn)

    assert has_element?(view, "#upload-form input[name='name'][disabled]")
    assert render(view) =~ "Select a file first"
  end

  test "a file of the wrong type is rejected", %{conn: conn} do
    view = open_modal(conn)

    {_audio, html} = pick_file(view, "notes.txt", "text/plain")

    assert html =~ "Invalid file type"
  end

  test "a file over the size limit is refused with a message", %{conn: conn} do
    previous = Application.get_env(:soundboard, :max_upload_bytes)
    Application.put_env(:soundboard, :max_upload_bytes, 10)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:soundboard, :max_upload_bytes, previous),
        else: Application.delete_env(:soundboard, :max_upload_bytes)
    end)

    view = open_modal(conn)
    {_audio, html} = pick_file(view)

    assert html =~ "File is too large"
    assert has_element?(view, "#upload-form button[type='submit'][disabled]")
  end
end
