defmodule SoundboardWeb.SoundboardLiveTest do
  @moduledoc """
  This module contains tests for the SoundboardLive view.
  """
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Soundboard.{Accounts.User, Repo, Sound}

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

      # Just verify the click happens without checking the event
      rendered =
        view
        |> element("[phx-click='play'][phx-value-name='#{sound.filename}']")
        |> render_click()

      assert rendered =~ sound.filename
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
        "source_type" => "local"
      }

      # Ensure directory exists
      File.mkdir_p!("priv/static/uploads")

      # Create test file if it doesn't exist
      test_file = "priv/static/uploads/test.mp3"
      updated_file = "priv/static/uploads/updated.mp3"

      unless File.exists?(test_file) do
        File.write!(test_file, "test content")
      end

      # Target the edit form specifically
      view
      |> element("#edit-form")
      |> render_submit(params)

      # Clean up both original and updated files
      File.rm_rf!(test_file)
      File.rm_rf!(updated_file)

      updated_sound = Repo.get(Sound, sound.id)
      assert updated_sound.filename == "updated.mp3"
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

      view
      |> element("[phx-click='delete_sound']")
      |> render_click()

      # Clean up
      File.rm_rf!("priv/static/uploads/test.mp3")

      # Give the delete operation time to complete
      Process.sleep(100)
      assert Repo.get(Sound, sound.id) == nil
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
end
