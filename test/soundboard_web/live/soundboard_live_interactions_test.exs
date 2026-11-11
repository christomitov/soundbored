defmodule SoundboardWeb.SoundboardLiveInteractionsTest do
  use SoundboardWeb.ConnCase, async: false

  import Mock
  import Phoenix.LiveViewTest

  alias Soundboard.Accounts.User
  alias Soundboard.{Favorites, PubSubTopics, Repo, Sound, Tag}

  setup %{conn: conn} do
    Repo.delete_all(Sound)
    Repo.delete_all(Tag)
    Repo.delete_all(User)

    user =
      %User{}
      |> User.changeset(%{username: "clicker", discord_id: "77", avatar: "c.jpg"})
      |> Repo.insert!()

    sound =
      %Sound{}
      |> Sound.changeset(%{filename: "honk.mp3", source_type: "local", user_id: user.id})
      |> Repo.insert!()

    {:ok, conn: init_test_session(conn, %{user_id: user.id}), user: user, sound: sound}
  end

  defp open_upload(view) do
    view |> element("[phx-click='show_upload_modal']") |> render_click()
    view |> element("select[name='source_type']") |> render_change(%{"source_type" => "url"})

    view
    |> element("#upload-form")
    |> render_change(%{"url" => "https://example.com/airhorn.mp3"})
  end

  defp open_edit(view, sound) do
    view |> element("[phx-click='edit'][phx-value-id='#{sound.id}']") |> render_click()
  end

  describe "upload modal" do
    test "tags, join/leave flags and volume are saved with the sound", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      open_upload(view)

      view
      |> element("#upload-tag-input")
      |> render_keydown(%{"key" => "Enter", "value" => "loud"})

      view
      |> element("#upload-tag-input")
      |> render_keydown(%{"key" => "Enter", "value" => "meme"})

      view |> element("[phx-click='remove_upload_tag'][phx-value-tag='meme']") |> render_click()
      view |> element("[phx-click='toggle_join_sound']") |> render_click()
      view |> element("[phx-click='toggle_leave_sound']") |> render_click()
      render_hook(view, "update_volume", %{"volume" => "40", "target" => "upload"})

      view
      |> element("#upload-form")
      |> render_submit(%{"url" => "https://example.com/airhorn.mp3", "name" => "airhorn"})

      sound =
        Sound
        |> Repo.get_by!(filename: "airhorn.mp3")
        |> Repo.preload([:tags, :user_sound_settings])

      assert Enum.map(sound.tags, & &1.name) == ["loud"]
      assert_in_delta sound.volume, 0.4, 0.0001
      assert [%{is_join_sound: true, is_leave_sound: true}] = sound.user_sound_settings
    end

    test "typing a tag suggests existing ones, and picking one adds it", %{conn: conn} do
      Repo.insert!(%Tag{name: "classic"})
      {:ok, view, _html} = live(conn, "/")
      open_upload(view)

      html =
        view
        |> element("#upload-tag-input")
        |> render_keyup(%{"key" => "c", "value" => "cla"})

      assert html =~ "classic"

      view
      |> element("[phx-click='select_upload_tag'][phx-value-tag='classic']")
      |> render_click()

      assert has_element?(view, "[phx-click='remove_upload_tag'][phx-value-tag='classic']")
    end

    test "Escape closes the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      open_upload(view)

      render_hook(view, "close_modal_key", %{"key" => "Escape"})

      refute has_element?(view, "#upload-form")
    end
  end

  describe "edit modal" do
    test "tags can be added, suggested and removed", %{conn: conn, sound: sound} do
      Repo.insert!(%Tag{name: "classic"})
      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      view |> element("#tag-input") |> render_keydown(%{"key" => "Enter", "value" => "funny"})
      assert tag_names(sound) == ["funny"]

      assert view |> element("#tag-input") |> render_keyup(%{"key" => "c", "value" => "cla"}) =~
               "classic"

      view |> element("[phx-click='select_tag'][phx-value-tag='classic']") |> render_click()
      assert Enum.sort(tag_names(sound)) == ["classic", "funny"]

      view |> element("[phx-click='remove_tag'][phx-value-tag='funny']") |> render_click()
      assert tag_names(sound) == ["classic"]
    end

    test "cancelling a delete keeps the sound", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      view |> element("[phx-click='show_delete_confirm']") |> render_click()
      view |> element("[phx-click='hide_delete_confirm']") |> render_click()

      refute has_element?(view, "[phx-click='delete_sound']")
      assert Repo.get(Sound, sound.id)
    end

    test "Escape closes the modal", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      render_hook(view, "close_modal_key", %{"key" => "Escape"})

      refute has_element?(view, "#edit-form")
    end
  end

  test "Escape with no modal open leaves the page as it is", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert render_hook(view, "close_modal_key", %{"key" => "Escape"}) =~ "honk"
    refute has_element?(view, "#upload-form")
    refute has_element?(view, "#edit-form")
  end

  test "starring a sound adds it to favorites", %{conn: conn, user: user, sound: sound} do
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("[phx-click='toggle_favorite'][phx-value-sound-id='#{sound.id}']")
      |> render_click()

    assert html =~ "Favorites updated!"
    assert sound.id in Favorites.list_favorites(user.id)
  end

  test "stop stops the bot and every browser player", %{conn: conn} do
    with_mock Soundboard.AudioPlayer, stop_sound: fn _guild_id -> :ok end do
      {:ok, view, _html} = live(conn, "/")

      view |> element("[phx-click='stop_sound']") |> render_click()

      assert_push_event(view, "stop-all-sounds", %{})
      assert_called(Soundboard.AudioPlayer.stop_sound(:_))
    end
  end

  test "more than twelve tags collapse behind a toggle", %{conn: conn, sound: sound} do
    tags =
      for n <- 1..13, do: Repo.insert!(%Tag{name: "tag#{String.pad_leading("#{n}", 2, "0")}"})

    sound
    |> Repo.preload(:tags)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:tags, tags)
    |> Repo.update!()

    {:ok, view, _html} = live(conn, "/")
    toggle = "[phx-click='toggle_tag_list']"
    last_tag = ".sm\\:hidden [phx-click='toggle_tag_filter'][phx-value-tag='tag13']"

    refute has_element?(view, last_tag)
    assert view |> element(toggle, "Show more tags") |> render_click()
    assert has_element?(view, last_tag)
    assert view |> element(toggle, "Show fewer tags") |> render_click()
    refute has_element?(view, last_tag)
  end

  describe "broadcasts" do
    test "a play elsewhere shows who played what", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      PubSubTopics.broadcast_sound_played("honk.mp3", "someone")

      assert render(view) =~ "someone played honk.mp3"
    end

    test "a playback error is shown, and the flash clears", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      PubSubTopics.broadcast_error("Bot is not in a voice channel")
      assert render(view) =~ "Bot is not in a voice channel"

      send(view.pid, :clear_flash)
      refute render(view) =~ "Bot is not in a voice channel"
    end

    test "a new upload elsewhere appears in the list", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/")

      %Sound{}
      |> Sound.changeset(%{filename: "fresh.mp3", source_type: "local", user_id: user.id})
      |> Repo.insert!()

      PubSubTopics.broadcast_files_updated()

      assert render(view) =~ "fresh"
    end
  end

  defp tag_names(sound) do
    Sound
    |> Repo.get!(sound.id)
    |> Repo.preload(:tags)
    |> Map.fetch!(:tags)
    |> Enum.map(& &1.name)
  end
end
