defmodule SoundboardWeb.SoundboardLive.EditTest do
  use SoundboardWeb.ConnCase, async: false

  import Ecto.Query

  alias Soundboard.{Accounts.User, Favorites, Repo, Sound, Tag, UploadsPath, UserSoundSetting}

  setup %{conn: conn} do
    user = Repo.insert!(%User{username: "editor", discord_id: "123", avatar: "e.jpg"})
    sound = insert_sound!(user, "test.mp3")

    {:ok, conn: init_test_session(conn, %{user_id: user.id}), user: user, sound: sound}
  end

  defp insert_sound!(user, filename, attrs \\ %{}) do
    %Sound{}
    |> Sound.changeset(
      Map.merge(%{filename: filename, source_type: "local", user_id: user.id}, attrs)
    )
    |> Repo.insert!()
  end

  defp insert_setting!(user, sound, flags) do
    %UserSoundSetting{}
    |> UserSoundSetting.changeset(Map.merge(%{user_id: user.id, sound_id: sound.id}, flags))
    |> Repo.insert!()
  end

  defp write_file!(sound) do
    path = UploadsPath.file_path(sound.storage_key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "ID3")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp open_edit(view, sound),
    do: view |> element("[phx-click='edit'][phx-value-id='#{sound.id}']") |> render_click()

  defp save(view, params), do: view |> element("#edit-form") |> render_submit(params)

  defp tag_names(sound) do
    Sound
    |> Repo.get!(sound.id)
    |> Repo.preload(:tags)
    |> Map.fetch!(:tags)
    |> Enum.map(& &1.name)
    |> Enum.sort()
  end

  defp setting(user, sound),
    do: Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: sound.id)

  describe "renaming" do
    test "keeps the file, tags, volume and my join and leave settings", %{
      conn: conn,
      user: user
    } do
      sound =
        insert_sound!(user, "keep.mp3", %{
          volume: 0.5,
          tags: [Repo.insert!(%Tag{name: "classic"})]
        })

      insert_setting!(user, sound, %{is_join_sound: true, is_leave_sound: true})
      path = write_file!(sound)

      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      assert save(view, %{"filename" => "updated"}) =~ "Sound updated successfully"
      refute has_element?(view, "#edit-form")

      updated = Repo.get!(Sound, sound.id)
      assert updated.filename == "updated.mp3"
      assert updated.storage_key == sound.storage_key
      assert File.exists?(path)
      assert_in_delta updated.volume, 0.5, 0.0001
      assert tag_names(sound) == ["classic"]
      assert %{is_join_sound: true, is_leave_sound: true} = setting(user, sound)
    end

    test "keeps a URL sound's URL", %{conn: conn, user: user} do
      sound =
        insert_sound!(user, "remote.mp3", %{
          source_type: "url",
          url: "https://example.com/remote.mp3"
        })

      {:ok, view, _html} = live(conn, "/")

      assert open_edit(view, sound) =~ "URL: https://example.com/remote.mp3"
      save(view, %{"filename" => "renamed"})

      assert %{filename: "renamed.mp3", url: "https://example.com/remote.mp3"} =
               Repo.get!(Sound, sound.id)
    end

    test "moving the volume slider changes the saved volume", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      render_hook(view, "update_volume", %{"volume" => 27, "target" => "edit"})

      assert has_element?(view, "#edit-volume-control input[name='volume'][value='27']")
      save(view, %{"filename" => "test"})
      assert_in_delta Repo.get!(Sound, sound.id).volume, 0.27, 0.0001
    end

    test "making a sound my join sound takes the join flag from my other sound only", %{
      conn: conn,
      user: user,
      sound: old
    } do
      insert_setting!(user, old, %{is_join_sound: true, is_leave_sound: true})
      new = insert_sound!(user, "new.mp3")

      {:ok, view, _html} = live(conn, "/")
      open_edit(view, new)
      save(view, %{"filename" => "new", "is_join_sound" => "true"})

      assert %{is_join_sound: false, is_leave_sound: true} = setting(user, old)
      assert %{is_join_sound: true, is_leave_sound: false} = setting(user, new)
    end

    test "a name already taken is flagged while typing", %{conn: conn, user: user} do
      current = insert_sound!(user, "current.wav")
      insert_sound!(user, "taken.wav")

      {:ok, view, _html} = live(conn, "/")
      open_edit(view, current)

      view
      |> element("#edit-form")
      |> render_change(%{"_target" => ["filename"], "filename" => "taken"})

      assert render(view) =~ "A sound with that name already exists"
      assert has_element?(view, "#edit-form button[type='submit'][disabled]")
    end

    test "saving a name already taken keeps the modal open with an error", %{
      conn: conn,
      user: user,
      sound: sound
    } do
      insert_sound!(user, "conflict.mp3")

      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      assert save(view, %{"filename" => "conflict"}) =~
               "Error updating sound: filename has already been taken"

      assert has_element?(view, "#edit-form")
      assert Repo.get!(Sound, sound.id).filename == "test.mp3"
    end

    test "a blank name is refused", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      assert save(view, %{"filename" => "   "}) =~
               "Error updating sound: filename can&#39;t be blank"

      assert has_element?(view, "#edit-form")

      assert render_submit(view, "save_sound", %{"sound_id" => sound.id}) =~
               "filename can&#39;t be blank"

      assert Repo.get!(Sound, sound.id).filename == "test.mp3"
    end
  end

  describe "tags" do
    test "can be added, suggested, reused and removed", %{conn: conn, sound: sound} do
      for n <- 0..9, do: Repo.insert!(%Tag{name: "a#{n}"})
      Repo.insert!(%Tag{name: "classic"})

      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      view |> element("#tag-input") |> render_keydown(%{"key" => "Enter", "value" => "funny"})
      assert tag_names(sound) == ["funny"]

      assert view |> element("#tag-input") |> render_keyup(%{"key" => "a", "value" => "CLA"}) =~
               "classic"

      view |> element("[phx-click='select_tag'][phx-value-tag='classic']") |> render_click()
      assert tag_names(sound) == ["classic", "funny"]

      view |> element("#tag-input") |> render_keydown(%{"key" => "Enter", "value" => " CLASSIC "})
      assert tag_names(sound) == ["classic", "funny"]
      assert Repo.aggregate(from(t in Tag, where: t.name == "classic"), :count) == 1

      view |> element("[phx-click='remove_tag'][phx-value-tag='funny']") |> render_click()
      view |> element("[phx-click='remove_tag'][phx-value-tag='classic']") |> render_click()
      assert tag_names(sound) == []
    end
  end

  describe "deleting" do
    test "removes the sound, its file, and everyone's favorites, settings and tags for it", %{
      conn: conn,
      user: user,
      sound: sound
    } do
      path = write_file!(sound)
      insert_setting!(user, sound, %{is_join_sound: true})
      {:ok, _favorite} = Favorites.toggle_favorite(user.id, sound.id)

      sound
      |> Repo.preload(:tags)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:tags, [Repo.insert!(%Tag{name: "doomed"})])
      |> Repo.update!()

      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)
      view |> element("[phx-click='show_delete_confirm']") |> render_click()

      assert view |> element("[phx-click='delete_sound']") |> render_click() =~
               "Sound deleted successfully"

      refute Repo.get(Sound, sound.id)
      refute File.exists?(path)
      assert Favorites.list_favorites(user.id) == []
      refute Repo.get_by(UserSoundSetting, sound_id: sound.id)

      assert Repo.aggregate(from(st in "sound_tags", where: st.sound_id == ^sound.id), :count) ==
               0
    end

    test "cancelling keeps the sound", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")
      open_edit(view, sound)

      view |> element("[phx-click='show_delete_confirm']") |> render_click()
      view |> element("[phx-click='hide_delete_confirm']") |> render_click()

      refute has_element?(view, "[phx-click='delete_sound']")
      assert Repo.get(Sound, sound.id)
    end

    test "a sound deleted in one session disappears from another, which can no longer save it",
         %{conn: conn, sound: sound} do
      {:ok, deleter, _html} = live(conn, "/")
      {:ok, watcher, _html} = live(conn, "/")
      card = "[phx-click='play'][phx-value-name='#{sound.filename}']"

      open_edit(watcher, sound)

      open_edit(deleter, sound)
      deleter |> element("[phx-click='show_delete_confirm']") |> render_click()
      deleter |> element("[phx-click='delete_sound']") |> render_click()

      refute has_element?(watcher, card)

      assert save(watcher, %{"filename" => "revived"}) =~ "Error updating sound"
      refute Repo.get_by(Sound, filename: "revived.mp3")
    end
  end

  describe "someone else's sound" do
    test "anyone signed in can edit it, but only its uploader can delete it", %{
      conn: conn,
      user: user
    } do
      owner = Repo.insert!(%User{username: "owner", discord_id: "456", avatar: "o.jpg"})
      shared = insert_sound!(owner, "shared.mp3")

      {:ok, view, _html} = live(conn, "/")

      refute open_edit(view, shared) =~ "Delete Sound"
      save(view, %{"filename" => "shared-renamed", "is_join_sound" => "true"})

      assert %{filename: "shared-renamed.mp3", user_id: owner_id} = Repo.get!(Sound, shared.id)
      assert owner_id == owner.id
      assert %{is_join_sound: true} = setting(user, shared)

      open_edit(view, shared)
      render_click(view, "show_delete_confirm")

      assert render_click(view, "delete_sound") =~ "You can only delete your own sounds"
      assert Repo.get(Sound, shared.id)
    end

    test "another guild's sound cannot be opened by a forged event", %{conn: conn, user: user} do
      foreign = insert_sound!(user, "foreign.mp3", %{guild_id: "other-guild"})

      {:ok, view, _html} = live(conn, "/")

      assert render_click(view, "edit", %{"id" => Integer.to_string(foreign.id)}) =~
               "Sound not found"

      refute has_element?(view, "#edit-form")
      assert Repo.get!(Sound, foreign.id).filename == "foreign.mp3"
    end

    test "an id that does not exist shows an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert render_click(view, "edit", %{"id" => "999999999"}) =~ "Sound not found"
      assert render_click(view, "edit", %{"id" => "not-an-id"}) =~ "Sound not found"
      refute has_element?(view, "#edit-form")
    end
  end

  test "Escape closes the modal", %{conn: conn, sound: sound} do
    {:ok, view, _html} = live(conn, "/")
    open_edit(view, sound)

    view
    |> element("[phx-window-keydown='close_modal_key']")
    |> render_keydown(%{"key" => "Escape"})

    refute has_element?(view, "#edit-form")
  end
end
