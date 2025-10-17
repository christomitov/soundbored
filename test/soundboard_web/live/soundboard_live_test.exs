defmodule SoundboardWeb.SoundboardLiveTest do
  @moduledoc """
  This module contains tests for the SoundboardLive view.
  """
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Soundboard.{Accounts.User, Repo, Sound, Tag}
  import Mock

  setup %{conn: conn} do
    # Clean up before tests
    Repo.delete_all(Sound)
    Repo.delete_all(User)

    # Create a test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser",
        discord_id: "123",
        avatar: "test.jpg"
      })
      |> Repo.insert()

    # Create a test sound
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert()

    # Set up the connection with a user session
    conn = conn |> init_test_session(%{user_id: user.id})

    {:ok, conn: conn, user: user, sound: sound}
  end

  describe "Soundboard LiveView" do
    test "mounts successfully with user session", %{conn: conn} do
      {:ok, _, html} = live(conn, "/")

      assert html =~ "Soundboard"
      # Check for the main content instead of a specific container
      assert html =~ "SoundBored"
    end

    test "can search sounds", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("form")
      |> render_change(%{"query" => "test"})

      rendered = render(view)
      assert rendered =~ "test.mp3"
    end

    test "can play sound", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _, _ -> :ok end do
        rendered =
          view
          |> element("[phx-click='play'][phx-value-name='#{sound.filename}']")
          |> render_click()

        assert rendered =~ sound.filename
      end
    end

    test "play random respects current search results", %{conn: conn, user: user} do
      %Sound{}
      |> Sound.changeset(%{
        filename: "filtered.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("form")
      |> render_change(%{"query" => "filtered"})

      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _, _ -> :ok end do
        view
        |> element("[phx-click='play_random']")
        |> render_click()

        assert_called(SoundboardWeb.AudioPlayer.play_sound("filtered.mp3", :_))
      end
    end

    test "play random respects selected tags", %{conn: conn, user: user} do
      tag =
        %Tag{}
        |> Tag.changeset(%{name: "funny"})
        |> Repo.insert!()

      %Sound{}
      |> Sound.changeset(%{
        filename: "funny.mp3",
        source_type: "local",
        user_id: user.id,
        tags: [tag]
      })
      |> Repo.insert!()

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("div.hidden.sm\\:flex button[phx-value-tag='funny']")
      |> render_click()

      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _, _ -> :ok end do
        view
        |> element("[phx-click='play_random']")
        |> render_click()

        assert_called(SoundboardWeb.AudioPlayer.play_sound("funny.mp3", :_))
      end
    end

    test "can open and close upload modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # First verify we can see the Add Sound button
      assert render(view) =~ "Add Sound"

      # Click the Add Sound button and verify modal appears
      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      # The modal should be visible now, verify its presence using form ID and content
      assert has_element?(view, "#upload-form")
      assert has_element?(view, "form[phx-submit='save_upload']")
      assert has_element?(view, "select[name='source_type']")
      assert render(view) =~ "Source Type"

      # Close the modal using the correct phx-click value
      view
      |> element("[phx-click='close_upload_modal']")
      |> render_click()

      # Verify modal is gone by checking for the form
      refute has_element?(view, "#upload-form")
    end

    test "can edit sound", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      rendered =
        view
        |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
        |> render_click()

      assert rendered =~ "Edit Sound"

      params = %{
        "filename" => "updated",
        "source_type" => "local",
        "volume" => "80"
      }

      # Ensure directory exists
      File.mkdir_p!("priv/static/uploads")

      # Create test file if it doesn't exist
      test_file = "priv/static/uploads/test.mp3"
      updated_file = "priv/static/uploads/updated.mp3"

      unless File.exists?(test_file) do
        File.write!(test_file, "test content")
      end

      # Seed playback cache with stale metadata to ensure it is cleared on update
      SoundboardWeb.AudioPlayer.invalidate_cache(sound.filename)
      SoundboardWeb.AudioPlayer.invalidate_cache("updated.mp3")

      :ets.insert(
        :sound_meta_cache,
        {sound.filename, %{source_type: "local", input: test_file, volume: 0.2}}
      )

      :ets.insert(
        :sound_meta_cache,
        {"updated.mp3", %{source_type: "local", input: updated_file, volume: 0.9}}
      )

      # Target the edit form specifically
      view
      |> element("#edit-form")
      |> render_submit(params)

      # Clean up both original and updated files
      File.rm_rf!(test_file)
      File.rm_rf!(updated_file)

      updated_sound = Repo.get(Sound, sound.id)
      assert updated_sound.filename == "updated.mp3"
      assert_in_delta updated_sound.volume, 0.64, 0.0001
      assert :ets.lookup(:sound_meta_cache, sound.filename) == []
      assert :ets.lookup(:sound_meta_cache, "updated.mp3") == []
    end

    test "slider volume change persists on save", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
      |> render_click()

      render_hook(view, :update_volume, %{"volume" => 27, "target" => "edit"})

      base_filename = Path.rootname(sound.filename)

      view
      |> element("#edit-form")
      |> render_submit(%{
        "filename" => base_filename,
        "source_type" => sound.source_type,
        "volume" => "27"
      })

      updated_sound = Repo.get!(Sound, sound.id)
      assert_in_delta updated_sound.volume, 0.0729, 0.0001
    end

    test "can delete sound", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      # Create temporary file for the test
      File.mkdir_p!("priv/static/uploads")
      File.write!("priv/static/uploads/test.mp3", "test content")

      view
      |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
      |> render_click()

      view
      |> element("[phx-click='show_delete_confirm']")
      |> render_click()

      # Seed cache entry to confirm deletion clears it
      SoundboardWeb.AudioPlayer.invalidate_cache(sound.filename)

      :ets.insert(
        :sound_meta_cache,
        {sound.filename,
         %{source_type: "local", input: "priv/static/uploads/test.mp3", volume: 0.5}}
      )

      view
      |> element("[phx-click='delete_sound']")
      |> render_click()

      # Clean up
      File.rm_rf!("priv/static/uploads/test.mp3")

      # Give the delete operation time to complete
      Process.sleep(100)
      assert Repo.get(Sound, sound.id) == nil
      assert :ets.lookup(:sound_meta_cache, sound.filename) == []
    end

    test "url upload allows setting url before name", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      view
      |> element("select[name='source_type']")
      |> render_change(%{"source_type" => "url"})

      html =
        view
        |> element("#upload-form")
        |> render_change(%{"url" => "https://example.com/beep.mp3"})

      refute html =~ "Please select a file"
      refute html =~ "can't be blank"
      assert html =~ "https://example.com/beep.mp3"
    end

    test "can upload sound from url", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      view
      |> element("select[name='source_type']")
      |> render_change(%{"source_type" => "url"})

      params = %{
        "url" => "https://example.com/wow.mp3",
        "name" => "wow"
      }

      view
      |> element("#upload-form")
      |> render_submit(params)

      new_sound = Repo.get_by!(Sound, filename: "wow.mp3")
      assert new_sound.source_type == "url"
      assert new_sound.url == "https://example.com/wow.mp3"
      assert new_sound.user_id == user.id

      Repo.delete!(new_sound)
    end

    test "upload sound from url saves provided volume", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='show_upload_modal']")
      |> render_click()

      view
      |> element("select[name='source_type']")
      |> render_change(%{"source_type" => "url"})

      view
      |> element("#upload-form")
      |> render_submit(%{
        "url" => "https://example.com/soft.mp3",
        "name" => "soft",
        "volume" => "25"
      })

      sound = Repo.get_by!(Sound, filename: "soft.mp3")
      assert_in_delta sound.volume, 0.0625, 0.0001

      Repo.delete!(sound)
    end

    test "deleting a local sound removes the file", %{conn: conn, sound: sound} do
      {:ok, view, _html} = live(conn, "/")

      uploads_dir = uploads_dir()
      File.mkdir_p!(uploads_dir)
      sound_path = Path.join(uploads_dir, sound.filename)
      File.write!(sound_path, "test content")

      view
      |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
      |> render_click()

      view
      |> element("[phx-click='show_delete_confirm']")
      |> render_click()

      view
      |> element("[phx-click='delete_sound']")
      |> render_click()

      Process.sleep(100)
      refute File.exists?(sound_path)
      assert Repo.get(Sound, sound.id) == nil
    end

    test "failed rename keeps original file", %{conn: conn, user: user, sound: sound} do
      {:ok, conflict_sound} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "conflict.mp3",
          source_type: "local",
          user_id: user.id
        })
        |> Repo.insert()

      uploads_dir = uploads_dir()
      File.mkdir_p!(uploads_dir)

      original_path = Path.join(uploads_dir, sound.filename)
      conflict_path = Path.join(uploads_dir, conflict_sound.filename)

      File.write!(original_path, "original")
      File.rm_rf!(conflict_path)

      on_exit(fn ->
        uploads_dir = uploads_dir()
        File.rm_rf!(Path.join(uploads_dir, sound.filename))
        File.rm_rf!(Path.join(uploads_dir, "conflict.mp3"))
      end)

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='edit'][phx-value-id='#{sound.id}']")
      |> render_click()

      _html =
        view
        |> element("#edit-form")
        |> render_submit(%{
          "filename" => "conflict",
          "source_type" => "local",
          "url" => "",
          "sound_id" => Integer.to_string(sound.id)
        })

      assert File.exists?(original_path)
      refute File.exists?(conflict_path)
      assert Repo.get!(Sound, sound.id).filename == sound.filename
    end

    test "handles pubsub updates", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      Phoenix.PubSub.broadcast(
        Soundboard.PubSub,
        "soundboard",
        {:files_updated}
      )

      # Just verify the view is still alive
      assert render(view) =~ "SoundBored"
    end
  end

  defp uploads_dir do
    Application.get_env(:soundboard, :uploads_dir, "priv/static/uploads")
  end
end
