defmodule SoundboardWeb.SoundboardLive.UploadTest do
  use SoundboardWeb.ConnCase, async: false

  alias Soundboard.{Accounts.User, Repo, Sound, Tag, Tenants, UploadsPath}

  setup %{conn: conn} do
    user = Repo.insert!(%User{username: "uploader", discord_id: "42", avatar: "a.jpg"})

    {:ok, conn: init_test_session(conn, %{user_id: user.id}), user: user}
  end

  defp open_modal(conn) do
    {:ok, view, _html} = live(conn, "/")
    view |> element("[phx-click='show_upload_modal']") |> render_click()
    view
  end

  defp pick_file(view, name \\ "beep.mp3", type \\ "audio/mpeg", content \\ "ID3fake-mp3-bytes") do
    audio =
      file_input(view, "#upload-form", :audio, [%{name: name, content: content, type: type}])

    {audio, view |> element("#upload-form") |> render_change(audio)}
  end

  defp choose_url(view) do
    view |> element("select[name='source_type']") |> render_change(%{"source_type" => "url"})
  end

  defp name_input(view), do: element(view, "#upload-form input[name='name']")
  defp submit(view, params), do: view |> element("#upload-form") |> render_submit(params)
  defp card(filename), do: "[phx-click='play'][phx-value-name='#{filename}']"

  defp insert_sound!(user, filename) do
    %Sound{}
    |> Sound.changeset(%{filename: filename, source_type: "local", user_id: user.id})
    |> Repo.insert!()
  end

  defp uploaded_files, do: UploadsPath.dir() |> File.ls() |> elem(1) |> MapSet.new()

  describe "a local file" do
    test "picking a file names the sound after it and enables the form", %{conn: conn} do
      view = open_modal(conn)

      assert has_element?(view, "#upload-form input[name='name'][disabled]")
      assert render(view) =~ "Select a file first"

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
      assert view |> element("#upload-selected-file") |> render() =~ "beep.mp3"
      assert has_element?(view, "label", "Change file")
      refute has_element?(view, "#upload-form button[type='submit'][disabled]")
      refute render(view) =~ "Select a file first"
    end

    test "saving stores the file under the chosen name and lists it", %{conn: conn, user: user} do
      view = open_modal(conn)
      {audio, _html} = pick_file(view)

      render_change(name_input(view), %{"name" => "renamed"})
      render_upload(audio, "beep.mp3")

      assert submit(view, %{"name" => "renamed"}) =~ "Sound added successfully"

      sound = Repo.get_by!(Sound, filename: "renamed.mp3")
      assert %{source_type: "local", user_id: user_id} = sound
      assert user_id == user.id
      assert File.read!(UploadsPath.file_path(sound.storage_key)) == "ID3fake-mp3-bytes"
      File.rm(UploadsPath.file_path(sound.storage_key))
      refute has_element?(view, "#upload-form")
      assert has_element?(view, card("renamed.mp3"))
    end

    test "a name already taken shows an error and blocks saving", %{conn: conn, user: user} do
      insert_sound!(user, "taken.mp3")

      view = open_modal(conn)
      pick_file(view)

      assert render_change(name_input(view), %{"name" => "taken"}) =~
               "A sound with that name already exists"

      assert has_element?(view, "#upload-form button[type='submit'][disabled]")
    end

    test "removing the picked file empties the form again", %{conn: conn} do
      view = open_modal(conn)
      pick_file(view)

      view |> element("#upload-selected-file button") |> render_click()

      refute has_element?(view, "#upload-selected-file")
      assert has_element?(view, "label", "Choose file")
      assert has_element?(view, "#upload-form input[name='name'][disabled]")
      assert has_element?(view, "#upload-form button[type='submit'][disabled]")
      assert render(view) =~ "Select a file first"
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

    test "a file of the wrong type is rejected", %{conn: conn} do
      view = open_modal(conn)

      {_audio, html} = pick_file(view, "notes.txt", "text/plain")

      assert html =~ "Invalid file type"

      assert has_element?(
               view,
               "#upload-file-errors",
               "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."
             )

      assert has_element?(view, "#upload-form button[type='submit'][disabled]")
    end

    test "a file whose bytes are not audio is refused and nothing is saved", %{conn: conn} do
      view = open_modal(conn)

      {audio, _html} =
        pick_file(view, "fake.mp3", "audio/mpeg", <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0::64>>)

      render_upload(audio, "fake.mp3")
      before = uploaded_files()

      assert submit(view, %{"name" => "fake"}) =~
               "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."

      assert has_element?(view, "#upload-form")
      refute Repo.get_by(Sound, filename: "fake.mp3")
      assert uploaded_files() == before
    end

    test "a file over the size limit is refused with a message", %{conn: conn} do
      previous = Application.get_env(:soundboard, :max_upload_bytes)
      Application.put_env(:soundboard, :max_upload_bytes, 10)
      on_exit(fn -> Application.put_env(:soundboard, :max_upload_bytes, previous) end)

      view = open_modal(conn)
      pick_file(view)

      assert has_element?(view, "#upload-file-errors", "File is too large")
      assert has_element?(view, "#upload-form button[type='submit'][disabled]")
    end

    test "a full guild refuses the upload and keeps no copy", %{conn: conn} do
      Repo.insert!(%Tenants.Guild{
        discord_guild_id: Tenants.default_guild_id(),
        slug: "full",
        max_storage_bytes: 1
      })

      view = open_modal(conn)
      {audio, _html} = pick_file(view)
      render_upload(audio, "beep.mp3")
      before = uploaded_files()

      assert submit(view, %{"name" => "beep"}) =~ "Storage limit reached for this soundboard"
      assert has_element?(view, "#upload-form")
      refute Repo.get_by(Sound, filename: "beep.mp3")
      assert uploaded_files() == before
    end
  end

  describe "a URL" do
    test "the name waits for a URL, then is taken from it", %{conn: conn} do
      view = open_modal(conn)
      choose_url(view)

      assert render(view) =~ "Enter a URL first to name it."
      assert has_element?(view, "#upload-form input[name='name'][disabled]")

      view |> element("#upload-form") |> render_change(%{"url" => "https://example.com/beep.mp3"})

      assert has_element?(view, "#upload-form input[name='name'][value='beep']")
      refute has_element?(view, "#upload-form input[name='name'][disabled]")
      refute has_element?(view, "#upload-form button[type='submit'][disabled]")
      refute render(view) =~ "Enter a URL first to name it."
    end

    test "saving stores the URL sound and lists it", %{conn: conn, user: user} do
      view = open_modal(conn)
      choose_url(view)

      assert submit(view, %{"url" => "https://example.com/wow.mp3", "name" => "wow"}) =~
               "Sound added successfully"

      assert %{source_type: "url", url: "https://example.com/wow.mp3", user_id: user_id} =
               Repo.get_by!(Sound, filename: "wow.mp3")

      assert user_id == user.id
      refute has_element?(view, "#upload-form")
      assert has_element?(view, card("wow.mp3"))
    end

    test "tags, join/leave flags and volume are saved with the sound", %{conn: conn} do
      view = open_modal(conn)
      choose_url(view)

      view
      |> element("#upload-form")
      |> render_change(%{"url" => "https://example.com/airhorn.mp3"})

      view
      |> element("#upload-tag-input")
      |> render_keydown(%{"key" => "Enter", "value" => "loud"})

      view
      |> element("#upload-tag-input")
      |> render_keydown(%{"key" => "Enter", "value" => "meme"})

      view |> element("[phx-click='remove_upload_tag'][phx-value-tag='meme']") |> render_click()
      view |> element("[phx-click='toggle_join_sound']") |> render_click()
      view |> element("[phx-click='toggle_leave_sound']") |> render_click()
      node = view |> element("#upload-volume-control") |> render() |> LazyHTML.from_fragment()
      [event] = LazyHTML.attribute(node, "data-push-event")
      [target] = LazyHTML.attribute(node, "data-volume-target")
      render_hook(view, event, %{"volume" => "40", "target" => target})

      submit(view, %{"url" => "https://example.com/airhorn.mp3", "name" => "airhorn"})

      sound =
        Sound
        |> Repo.get_by!(filename: "airhorn.mp3")
        |> Repo.preload([:tags, :user_sound_settings])

      assert Enum.map(sound.tags, & &1.name) == ["loud"]
      assert_in_delta sound.volume, 0.4, 0.0001
      assert [%{is_join_sound: true, is_leave_sound: true}] = sound.user_sound_settings
    end

    test "typing a tag suggests existing ones, and picking one adds it", %{conn: conn} do
      for n <- 0..9, do: Repo.insert!(%Tag{name: "a#{n}"})
      Repo.insert!(%Tag{name: "classic"})

      view = open_modal(conn)
      choose_url(view)

      view
      |> element("#upload-form")
      |> render_change(%{"url" => "https://example.com/airhorn.mp3"})

      assert view
             |> element("#upload-tag-input")
             |> render_keyup(%{"key" => "a", "value" => "cla"}) =~ "classic"

      view
      |> element("[phx-click='select_upload_tag'][phx-value-tag='classic']")
      |> render_click()

      assert has_element?(view, "[phx-click='remove_upload_tag'][phx-value-tag='classic']")
    end

    test "a name already taken is refused at save and the modal stays open", %{
      conn: conn,
      user: user
    } do
      insert_sound!(user, "taken.mp3")

      view = open_modal(conn)
      choose_url(view)

      assert submit(view, %{"url" => "https://example.com/taken.mp3", "name" => "taken"}) =~
               "A sound with that name already exists"

      assert has_element?(view, "#upload-form")
      assert Repo.aggregate(Sound, :count) == 1
    end
  end

  describe "closing" do
    test "the close button closes the modal", %{conn: conn} do
      view = open_modal(conn)

      view |> element("[phx-click='close_upload_modal']") |> render_click()

      refute has_element?(view, "#upload-form")
    end

    test "Escape closes the modal", %{conn: conn} do
      view = open_modal(conn)

      view
      |> element("[phx-window-keydown='close_modal_key']")
      |> render_keydown(%{"key" => "Escape"})

      refute has_element?(view, "#upload-form")
    end
  end
end
