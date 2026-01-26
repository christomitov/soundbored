defmodule SoundboardWeb.Live.UploadHandlerTest do
  @moduledoc """
  Test for the upload handler.
  """
  use SoundboardWeb.ConnCase

  alias Soundboard.Accounts.{Tenant, Tenants, User}
  alias SoundboardWeb.Live.UploadHandler
  alias Soundboard.{Repo, Sound, Tag}
  import Soundboard.DataCase, only: [errors_on: 1]

  setup do
    # Clean up before tests
    Repo.delete_all(Sound)
    Repo.delete_all(Tag)

    # Create a test user
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser",
        discord_id: "123",
        avatar: "test.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    # Create test tags
    {:ok, tag1} =
      %Tag{}
      |> Tag.changeset(%{name: "test_tag1", tenant_id: tenant.id})
      |> Repo.insert()

    {:ok, tag2} =
      %Tag{}
      |> Tag.changeset(%{name: "test_tag2", tenant_id: tenant.id})
      |> Repo.insert()

    # Create a mock socket with necessary assigns and valid upload entry
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        current_user: user,
        current_tenant: tenant,
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

    {:ok, socket: socket, user: user, tags: [tag1, tag2], tenant: tenant}
  end

  describe "validate_upload/2" do
    test "validates URL upload with valid params", %{socket: socket} do
      params = %{
        "source_type" => "url",
        "name" => "test_sound",
        "url" => "http://example.com/test.mp3"
      }

      assert {:ok, _socket} = UploadHandler.validate_upload(socket, params)
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
    test "returns an error when tenant sound limit is reached", %{socket: socket, tenant: tenant} do
      {:ok, updated_tenant} =
        tenant
        |> Tenant.changeset(%{max_sounds: 0})
        |> Repo.update()

      socket = put_in(socket.assigns.current_tenant, updated_tenant)

      params = %{
        "source_type" => "url",
        "name" => "limited",
        "url" => "http://example.com/test.mp3"
      }

      assert {:error, message, _socket} = UploadHandler.handle_upload(socket, params, & &1)
      assert message =~ "Sound limit"
    end

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

    test "persists provided volume percentage", %{socket: socket} do
      params = %{
        "source_type" => "url",
        "name" => "quiet_sound",
        "url" => "http://example.com/quiet.mp3",
        "volume" => "40"
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)
      assert_in_delta sound.volume, 0.4, 0.0001
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

  describe "join/leave sound handling via handle_upload/3" do
    test "URL upload with is_join_sound: true creates UserSoundSetting", %{
      socket: socket,
      user: user
    } do
      params = %{
        "source_type" => "url",
        "name" => "join_sound_test",
        "url" => "http://example.com/join.mp3",
        "is_join_sound" => true,
        "is_leave_sound" => false
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)

      # Verify user sound setting was created with correct flags
      setting = Repo.get_by(Soundboard.UserSoundSetting, sound_id: sound.id, user_id: user.id)
      assert setting != nil
      assert setting.is_join_sound == true
      assert setting.is_leave_sound == false
    end

    test "URL upload with is_join_sound: 'true' (string) creates UserSoundSetting", %{
      socket: socket,
      user: user
    } do
      params = %{
        "source_type" => "url",
        "name" => "join_sound_string_test",
        "url" => "http://example.com/join_string.mp3",
        "is_join_sound" => "true",
        "is_leave_sound" => "false"
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)

      # Verify user sound setting was created with correct flags
      setting = Repo.get_by(Soundboard.UserSoundSetting, sound_id: sound.id, user_id: user.id)
      assert setting != nil
      assert setting.is_join_sound == true
      assert setting.is_leave_sound == false
    end

    test "URL upload with is_leave_sound: true creates UserSoundSetting", %{
      socket: socket,
      user: user
    } do
      params = %{
        "source_type" => "url",
        "name" => "leave_sound_test",
        "url" => "http://example.com/leave.mp3",
        "is_join_sound" => false,
        "is_leave_sound" => true
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)

      # Verify user sound setting was created with correct flags
      setting = Repo.get_by(Soundboard.UserSoundSetting, sound_id: sound.id, user_id: user.id)
      assert setting != nil
      assert setting.is_join_sound == false
      assert setting.is_leave_sound == true
    end

    test "URL upload with is_leave_sound: 'true' (string) creates UserSoundSetting", %{
      socket: socket,
      user: user
    } do
      params = %{
        "source_type" => "url",
        "name" => "leave_sound_string_test",
        "url" => "http://example.com/leave_string.mp3",
        "is_join_sound" => "false",
        "is_leave_sound" => "true"
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)

      # Verify user sound setting was created with correct flags
      setting = Repo.get_by(Soundboard.UserSoundSetting, sound_id: sound.id, user_id: user.id)
      assert setting != nil
      assert setting.is_join_sound == false
      assert setting.is_leave_sound == true
    end

    test "URL upload with both flags false creates UserSoundSetting with false flags", %{
      socket: socket,
      user: user
    } do
      params = %{
        "source_type" => "url",
        "name" => "normal_sound_test",
        "url" => "http://example.com/normal.mp3",
        "is_join_sound" => false,
        "is_leave_sound" => false
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)

      # Verify user sound setting was created with false flags
      setting = Repo.get_by(Soundboard.UserSoundSetting, sound_id: sound.id, user_id: user.id)
      assert setting != nil
      assert setting.is_join_sound == false
      assert setting.is_leave_sound == false
    end

    test "URL upload with nil flags creates UserSoundSetting with false flags", %{
      socket: socket,
      user: user
    } do
      params = %{
        "source_type" => "url",
        "name" => "nil_flags_test",
        "url" => "http://example.com/nil_flags.mp3",
        "is_join_sound" => nil,
        "is_leave_sound" => nil
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)

      # Verify user sound setting was created with false flags
      setting = Repo.get_by(Soundboard.UserSoundSetting, sound_id: sound.id, user_id: user.id)
      assert setting != nil
      assert setting.is_join_sound == false
      assert setting.is_leave_sound == false
    end

    test "URL upload with 'false' string flags creates UserSoundSetting with false flags", %{
      socket: socket,
      user: user
    } do
      params = %{
        "source_type" => "url",
        "name" => "false_string_test",
        "url" => "http://example.com/false_string.mp3",
        "is_join_sound" => "false",
        "is_leave_sound" => "false"
      }

      assert {:ok, sound} = UploadHandler.handle_upload(socket, params, & &1)

      # Verify user sound setting was created with false flags
      setting = Repo.get_by(Soundboard.UserSoundSetting, sound_id: sound.id, user_id: user.id)
      assert setting != nil
      assert setting.is_join_sound == false
      assert setting.is_leave_sound == false
    end

    test "clears existing join sound setting when new join sound is set", %{
      socket: socket,
      user: user
    } do
      # First create a sound with is_join_sound: true
      params1 = %{
        "source_type" => "url",
        "name" => "first_join_sound",
        "url" => "http://example.com/first_join.mp3",
        "is_join_sound" => true,
        "is_leave_sound" => false
      }

      assert {:ok, first_sound} = UploadHandler.handle_upload(socket, params1, & &1)

      first_setting =
        Repo.get_by(Soundboard.UserSoundSetting, sound_id: first_sound.id, user_id: user.id)

      assert first_setting.is_join_sound == true

      # Now create another sound with is_join_sound: true
      params2 = %{
        "source_type" => "url",
        "name" => "second_join_sound",
        "url" => "http://example.com/second_join.mp3",
        "is_join_sound" => true,
        "is_leave_sound" => false
      }

      assert {:ok, second_sound} = UploadHandler.handle_upload(socket, params2, & &1)

      # The first setting should now have is_join_sound: false
      first_setting_reloaded = Repo.get!(Soundboard.UserSoundSetting, first_setting.id)
      assert first_setting_reloaded.is_join_sound == false

      # The second setting should have is_join_sound: true
      second_setting =
        Repo.get_by(Soundboard.UserSoundSetting, sound_id: second_sound.id, user_id: user.id)

      assert second_setting.is_join_sound == true
    end

    test "clears existing leave sound setting when new leave sound is set", %{
      socket: socket,
      user: user
    } do
      # First create a sound with is_leave_sound: true
      params1 = %{
        "source_type" => "url",
        "name" => "first_leave_sound",
        "url" => "http://example.com/first_leave.mp3",
        "is_join_sound" => false,
        "is_leave_sound" => true
      }

      assert {:ok, first_sound} = UploadHandler.handle_upload(socket, params1, & &1)

      first_setting =
        Repo.get_by(Soundboard.UserSoundSetting, sound_id: first_sound.id, user_id: user.id)

      assert first_setting.is_leave_sound == true

      # Now create another sound with is_leave_sound: true
      params2 = %{
        "source_type" => "url",
        "name" => "second_leave_sound",
        "url" => "http://example.com/second_leave.mp3",
        "is_join_sound" => false,
        "is_leave_sound" => true
      }

      assert {:ok, second_sound} = UploadHandler.handle_upload(socket, params2, & &1)

      # The first setting should now have is_leave_sound: false
      first_setting_reloaded = Repo.get!(Soundboard.UserSoundSetting, first_setting.id)
      assert first_setting_reloaded.is_leave_sound == false

      # The second setting should have is_leave_sound: true
      second_setting =
        Repo.get_by(Soundboard.UserSoundSetting, sound_id: second_sound.id, user_id: user.id)

      assert second_setting.is_leave_sound == true
    end
  end
end
