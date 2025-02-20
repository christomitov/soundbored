defmodule SoundboardWeb.Live.UploadHandlerTest do
  @moduledoc """
  Test for the upload handler.
  """
  use SoundboardWeb.ConnCase

  alias Soundboard.Accounts.User
  alias SoundboardWeb.Live.UploadHandler
  alias Soundboard.{Repo, Sound, Tag}
  import Soundboard.DataCase, only: [errors_on: 1]

  setup do
    # Clean up before tests
    Repo.delete_all(Sound)
    Repo.delete_all(Tag)

    # Create a test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser",
        discord_id: "123",
        avatar: "test.jpg"
      })
      |> Repo.insert()

    # Create test tags
    {:ok, tag1} = %Tag{name: "test_tag1"} |> Repo.insert()
    {:ok, tag2} = %Tag{name: "test_tag2"} |> Repo.insert()

    # Create a mock socket with necessary assigns and valid upload entry
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        current_user: user,
        upload_tags: [tag1, tag2],
        uploads: %{
          audio: %Phoenix.LiveView.UploadConfig{
            entries: [
              %Phoenix.LiveView.UploadEntry{
                client_name: "test.mp3",
                client_type: "audio/mpeg",
                ref: "abc123",
                valid?: true,
                done?: false,
                cancelled?: false,
                progress: 0,
                uuid: "test-uuid"
              }
            ]
          }
        }
      }
    }

    {:ok, socket: socket, user: user, tags: [tag1, tag2]}
  end

  describe "validate_upload/2" do
    test "validates URL upload with valid params", %{socket: socket} do
      params = %{
        "source_type" => "url",
        "name" => "test_sound",
        "url" => "http://example.com/test.mp3"
      }

      # We should expect an error since validation requires user_id
      assert {:error, changeset} = UploadHandler.validate_upload(socket, params)
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "validates URL upload with missing params", %{socket: socket} do
      params = %{"source_type" => "url"}
      assert {:ok, _socket} = UploadHandler.validate_upload(socket, params)
    end

    test "validates local upload with valid name", %{socket: socket} do
      params = %{"name" => "test_sound"}
      assert {:ok, _socket} = UploadHandler.validate_upload(socket, params)
    end

    test "validates local upload with duplicate name", %{socket: socket, user: user} do
      # Create existing sound
      {:ok, _sound} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "test_sound.mp3",
          user_id: user.id,
          source_type: "local"
        })
        |> Repo.insert()

      params = %{"name" => "test_sound"}
      assert {:error, changeset} = UploadHandler.validate_upload(socket, params)
      assert "has already been taken" in errors_on(changeset).filename
    end

    test "validates local upload with missing file", %{socket: socket} do
      socket = put_in(socket.assigns.uploads.audio.entries, [])
      params = %{}
      assert {:error, changeset} = UploadHandler.validate_upload(socket, params)
      assert "Please select a file" in errors_on(changeset).file
    end
  end

  describe "handle_upload/3" do
    test "handles URL upload successfully", %{socket: socket, user: user} do
      params = %{
        "source_type" => "url",
        "name" => "test_url_sound",
        "url" => "http://example.com/test.mp3"
      }

      # First clear any existing sounds
      Repo.delete_all(Sound)

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)
      assert sound.filename == "test_url_sound.mp3"
      assert sound.url == "http://example.com/test.mp3"
      assert sound.user_id == user.id
      assert sound.source_type == "url"
    end

    test "handles upload with tags", %{socket: socket, tags: [tag1, _tag2]} do
      params = %{
        "source_type" => "url",
        "name" => "tagged_sound",
        "url" => "http://example.com/test.mp3"
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)

      # Verify tags were associated
      sound = Repo.preload(sound, :tags)
      assert Enum.any?(sound.tags, fn t -> t.id == tag1.id end)
    end

    test "handles upload errors", %{socket: socket} do
      params = %{
        "source_type" => "local",
        "name" => "error_sound"
      }

      # Mock failing consume function
      consume_fn = fn _socket, :audio, _func -> {:error, "Error saving file"} end

      assert {:error, message, _socket} = UploadHandler.handle_upload(socket, params, consume_fn)
      assert message == "Error saving file"
    end
  end
end
