defmodule SoundboardWeb.API.SoundControllerTest do
  @moduledoc """
  Test for the SoundController.
  """
  use SoundboardWeb.ConnCase

  import Mock

  alias Soundboard.Accounts.{ApiTokens, User}
  alias Soundboard.{Repo, Sound, Tag, UserSoundSetting}

  setup %{conn: conn} do
    user = insert_user()
    sound = insert_sound(user)
    tag = insert_tag()

    {:ok, raw_token, _token} = ApiTokens.generate_token(user, %{label: "API Test"})

    insert_sound_tag(sound, tag)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> raw_token)

    %{conn: conn, sound: sound, user: user}
  end

  describe "index" do
    test "lists all sounds with their tags", %{conn: conn} do
      conn = get(conn, ~p"/api/sounds")
      assert %{"data" => sounds} = json_response(conn, 200)

      Enum.each(sounds, fn sound_data ->
        assert is_integer(sound_data["id"])
        assert is_binary(sound_data["filename"])
        assert is_list(sound_data["tags"])
        assert sound_data["inserted_at"]
        assert sound_data["updated_at"]
      end)
    end

    test "returns sounds in expected format", %{conn: conn, sound: sound} do
      conn = get(conn, ~p"/api/sounds")
      assert %{"data" => sounds} = json_response(conn, 200)

      test_sound = Enum.find(sounds, &(&1["id"] == sound.id))
      assert test_sound
      assert test_sound["filename"] == sound.filename
      assert is_list(test_sound["tags"])
    end

    test "includes join and leave flags for the authenticated user", %{
      conn: conn,
      sound: sound,
      user: user
    } do
      %UserSoundSetting{}
      |> UserSoundSetting.changeset(%{
        user_id: user.id,
        sound_id: sound.id,
        is_join_sound: true,
        is_leave_sound: false
      })
      |> Repo.insert!()

      conn = get(conn, ~p"/api/sounds")
      assert %{"data" => sounds} = json_response(conn, 200)

      test_sound = Enum.find(sounds, &(&1["id"] == sound.id))
      assert test_sound["is_join_sound"] == true
      assert test_sound["is_leave_sound"] == false
    end
  end

  describe "create" do
    test "creates a URL sound", %{conn: conn, user: user} do
      name = "api_url_#{System.unique_integer([:positive])}"

      conn =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "url",
          "name" => name,
          "url" => "https://example.com/wow.mp3",
          "tags" => ["meme", "reaction"],
          "volume" => "35",
          "is_join_sound" => "true"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["filename"] == "#{name}.mp3"
      assert data["source_type"] == "url"
      assert data["url"] == "https://example.com/wow.mp3"
      assert data["is_join_sound"] == true

      sound = Repo.get_by!(Sound, filename: "#{name}.mp3") |> Repo.preload(:tags)
      assert Enum.sort(Enum.map(sound.tags, & &1.name)) == ["meme", "reaction"]
      assert_in_delta sound.volume, 0.35, 0.0001

      setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: sound.id)
      assert setting.is_join_sound
      refute setting.is_leave_sound
    end

    test "infers URL source type when source_type is omitted", %{conn: conn} do
      name = "api_url_inferred_#{System.unique_integer([:positive])}"

      conn =
        post(conn, ~p"/api/sounds", %{
          "name" => name,
          "url" => "https://example.com/inferred.mp3"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["source_type"] == "url"
      assert data["filename"] == "#{name}.mp3"
    end

    test "creates a local multipart sound and saves the file", %{conn: conn} do
      name = "api_local_#{System.unique_integer([:positive])}"
      tmp_path = temp_upload_path("sample.mp3")
      File.write!(tmp_path, "audio")

      on_exit(fn -> File.rm(tmp_path) end)

      upload = %Plug.Upload{path: tmp_path, filename: "sample.mp3", content_type: "audio/mpeg"}

      conn =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "local",
          "name" => name,
          "file" => upload,
          "tags" => "api,local",
          "volume" => "120",
          "is_leave_sound" => "true"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["filename"] == "#{name}.mp3"
      assert data["source_type"] == "local"
      assert data["is_leave_sound"] == true

      sound = Repo.get_by!(Sound, filename: "#{name}.mp3")
      assert_in_delta sound.volume, 1.2, 0.0001

      copied_file = Path.join(uploads_dir(), sound.filename)
      assert File.exists?(copied_file)

      on_exit(fn -> File.rm(copied_file) end)
    end

    test "infers local source type when multipart file is present", %{conn: conn} do
      name = "api_local_inferred_#{System.unique_integer([:positive])}"
      tmp_path = temp_upload_path("inferred.mp3")
      File.write!(tmp_path, "audio")

      on_exit(fn -> File.rm(tmp_path) end)

      upload = %Plug.Upload{path: tmp_path, filename: "inferred.mp3", content_type: "audio/mpeg"}

      conn =
        post(conn, ~p"/api/sounds", %{
          "name" => name,
          "file" => upload
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["source_type"] == "local"
      assert data["filename"] == "#{name}.mp3"

      on_exit(fn -> File.rm(Path.join(uploads_dir(), "#{name}.mp3")) end)
    end

    test "clears previous join sound when creating a new join sound", %{conn: conn, user: user} do
      first_name = "join_one_#{System.unique_integer([:positive])}"
      second_name = "join_two_#{System.unique_integer([:positive])}"

      _ =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "url",
          "name" => first_name,
          "url" => "https://example.com/first.mp3",
          "is_join_sound" => "true"
        })

      _ =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "url",
          "name" => second_name,
          "url" => "https://example.com/second.mp3",
          "is_join_sound" => "true"
        })

      first_sound = Repo.get_by!(Sound, filename: "#{first_name}.mp3")
      second_sound = Repo.get_by!(Sound, filename: "#{second_name}.mp3")

      first_setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: first_sound.id)
      second_setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: second_sound.id)

      refute first_setting.is_join_sound
      assert second_setting.is_join_sound
    end

    test "returns validation errors for missing fields", %{conn: conn} do
      conn_missing_name =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "url",
          "url" => "https://example.com/missing-name.mp3"
        })

      assert %{"errors" => errors} = json_response(conn_missing_name, 422)
      assert "can't be blank" in errors["filename"]

      conn_missing_url =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "url",
          "name" => "missing_url"
        })

      assert %{"errors" => errors} = json_response(conn_missing_url, 422)
      assert "can't be blank" in errors["url"]

      conn_missing_file =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "local",
          "name" => "missing_file"
        })

      assert %{"errors" => errors} = json_response(conn_missing_file, 422)
      assert "Please select a file" in errors["file"]
    end

    test "returns validation error for duplicate filename", %{conn: conn, user: user} do
      duplicate_name = "dup_#{System.unique_integer([:positive])}"

      {:ok, _} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "#{duplicate_name}.mp3",
          source_type: "url",
          url: "https://example.com/original.mp3",
          user_id: user.id
        })
        |> Repo.insert()

      conn =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "url",
          "name" => duplicate_name,
          "url" => "https://example.com/new.mp3"
        })

      assert %{"errors" => errors} = json_response(conn, 422)
      assert "has already been taken" in errors["filename"]
    end

    test "returns unauthorized without valid token" do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer badtoken")
        |> post(~p"/api/sounds", %{
          "source_type" => "url",
          "name" => "invalid",
          "url" => "https://example.com/test.mp3"
        })

      assert json_response(conn, 401)
    end
  end

  describe "play" do
    test "plays a sound as the authenticated token user", %{conn: conn, sound: sound, user: user} do
      actor = %{display_name: user.username, user_id: user.id}

      with_mock Soundboard.AudioPlayer, play_sound: fn _filename, _actor -> :ok end do
        conn = post(conn, ~p"/api/sounds/#{sound.id}/play")

        assert %{
                 "data" => %{
                   "status" => "accepted",
                   "message" => "Playback request accepted for " <> _,
                   "requested_by" => requested_by,
                   "sound" => %{"id" => sound_id, "filename" => filename}
                 }
               } = json_response(conn, 202)

        assert requested_by == user.username
        assert sound_id == sound.id
        assert filename == sound.filename
        assert_called(Soundboard.AudioPlayer.play_sound(sound.filename, actor))
      end
    end

    test "ignores x-username and attributes playback to the token user", %{
      conn: conn,
      sound: sound,
      user: user
    } do
      actor = %{display_name: user.username, user_id: user.id}

      with_mock Soundboard.AudioPlayer, play_sound: fn _filename, _actor -> :ok end do
        conn =
          conn
          |> put_req_header("x-username", "TestUser")
          |> post(~p"/api/sounds/#{sound.id}/play")

        assert %{
                 "data" => %{
                   "requested_by" => requested_by,
                   "sound" => %{"id" => sound_id, "filename" => filename}
                 }
               } = json_response(conn, 202)

        assert requested_by == user.username
        assert sound_id == sound.id
        assert filename == sound.filename
        assert_called(Soundboard.AudioPlayer.play_sound(sound.filename, actor))
      end
    end

    test "returns error when sound not found", %{conn: conn} do
      with_mock Soundboard.AudioPlayer, play_sound: fn _filename, _username -> :ok end do
        conn = post(conn, ~p"/api/sounds/999999/play")
        assert %{"error" => "Sound not found"} = json_response(conn, 404)
      end
    end

    test "returns unauthorized without valid API token" do
      conn = build_conn()
      conn = post(conn, ~p"/api/sounds/1/play")
      assert json_response(conn, 401)
    end
  end

  defp insert_sound(user) do
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test_sound#{System.unique_integer([:positive])}.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert()

    sound
  end

  defp insert_tag do
    {:ok, tag} =
      %Tag{}
      |> Tag.changeset(%{name: "test_tag#{System.unique_integer([:positive])}"})
      |> Repo.insert()

    tag
  end

  defp insert_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer([:positive])}",
        discord_id: "#{System.unique_integer([:positive])}",
        avatar: "test_avatar.jpg"
      })
      |> Repo.insert()

    user
  end

  defp insert_sound_tag(sound, tag) do
    {:ok, _} =
      %Soundboard.SoundTag{}
      |> Soundboard.SoundTag.changeset(%{
        sound_id: sound.id,
        tag_id: tag.id
      })
      |> Repo.insert()
  end

  defp uploads_dir do
    Soundboard.UploadsPath.dir()
  end

  defp temp_upload_path(filename) do
    Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{filename}")
  end
end
