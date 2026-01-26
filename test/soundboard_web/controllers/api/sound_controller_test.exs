defmodule SoundboardWeb.API.SoundControllerTest do
  @moduledoc """
  Test for the SoundController.
  """
  use SoundboardWeb.ConnCase
  alias Soundboard.Accounts.{ApiTokens, Tenants, User}
  alias Soundboard.{Repo, Sound, Tag}
  import Mock

  setup %{conn: conn} do
    user = insert_user()
    sound = insert_sound(user)
    tag = insert_tag()

    {:ok, raw_token, _token} = ApiTokens.generate_token(user, %{label: "API Test"})

    # Add tag to sound
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

      # Verify response structure for each sound
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

      # Find our test sound in the results
      test_sound = Enum.find(sounds, &(&1["id"] == sound.id))
      assert test_sound
      assert test_sound["filename"] == sound.filename
      assert is_list(test_sound["tags"])
    end
  end

  describe "play" do
    test "plays a sound successfully", %{conn: conn, sound: sound, user: user} do
      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _filename, _username -> :ok end do
        conn =
          conn
          |> put_req_header("x-username", "TestUser")
          |> post(~p"/api/sounds/#{sound.id}/play")

        assert %{
                 "status" => "success",
                 "message" => "Playing sound: " <> _,
                 "played_by" => played_by
               } = json_response(conn, 200)

        assert played_by == user.username
      end
    end

    test "plays a sound with default username when x-username not provided", %{
      conn: conn,
      sound: sound,
      user: user
    } do
      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _filename, _username -> :ok end do
        conn = post(conn, ~p"/api/sounds/#{sound.id}/play")

        assert %{
                 "status" => "success",
                 "message" => "Playing sound: " <> _,
                 "played_by" => played_by
               } = json_response(conn, 200)

        assert played_by == user.username
      end
    end

    test "returns error when sound not found", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _filename, _username -> :ok end do
        conn = post(conn, ~p"/api/sounds/999999/play")
        assert %{"error" => "Sound not found"} = json_response(conn, 404)
      end
    end

    test "handles invalid string ID gracefully", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _filename, _username -> :ok end do
        conn = post(conn, ~p"/api/sounds/invalid-id/play")
        assert %{"error" => "Sound not found"} = json_response(conn, 404)
      end
    end

    test "returns unauthorized without valid API token" do
      conn = build_conn()
      conn = post(conn, ~p"/api/sounds/1/play")
      assert json_response(conn, 401)
    end
  end

  describe "stop" do
    test "stops sounds successfully", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer, stop_sound: fn _tenant_id -> :ok end do
        conn = post(conn, ~p"/api/sounds/stop")

        assert %{
                 "status" => "success",
                 "message" => "Stopped all sounds"
               } = json_response(conn, 200)

        assert called(SoundboardWeb.AudioPlayer.stop_sound(:_))
      end
    end

    test "returns unauthorized without valid API token" do
      conn = build_conn()
      conn = post(conn, ~p"/api/sounds/stop")
      assert json_response(conn, 401)
    end
  end

  describe "play_stream" do
    test "plays streamed audio successfully", %{conn: conn, user: user} do
      with_mock SoundboardWeb.AudioPlayer, play_url: fn _path, _volume, _username -> :ok end do
        audio_data = <<0xFF, 0xFB, 0x90, 0x00>>

        conn =
          conn
          |> put_req_header("content-type", "audio/mpeg")
          |> post(~p"/api/sounds/play-stream", audio_data)

        assert %{
                 "status" => "success",
                 "message" => "Playing streamed audio",
                 "played_by" => played_by
               } = json_response(conn, 200)

        assert played_by == user.username
        assert called(SoundboardWeb.AudioPlayer.play_url(:_, :_, :_))
      end
    end

    test "returns error when no audio data provided", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer, play_url: fn _path, _volume, _username -> :ok end do
        conn =
          conn
          |> put_req_header("content-type", "audio/mpeg")
          |> post(~p"/api/sounds/play-stream", "")

        assert %{"error" => "No audio data received"} = json_response(conn, 400)
        refute called(SoundboardWeb.AudioPlayer.play_url(:_, :_, :_))
      end
    end

    test "uses x-username header when no authenticated user", %{conn: _conn} do
      # Create a new token-only connection without a user in assigns
      tenant = Tenants.ensure_default_tenant!()

      {:ok, api_user} =
        Repo.insert(%User{
          username: "api-only-user",
          discord_id: "#{System.unique_integer([:positive])}",
          avatar: "test.jpg",
          tenant_id: tenant.id
        })

      {:ok, raw_token, _token} = ApiTokens.generate_token(api_user, %{label: "Stream Test"})

      with_mock SoundboardWeb.AudioPlayer,
        play_url: fn _path, _volume, username ->
          send(self(), {:played_with_username, username})
          :ok
        end do
        audio_data = <<0xFF, 0xFB, 0x90, 0x00>>

        conn =
          build_conn()
          |> put_req_header("authorization", "Bearer " <> raw_token)
          |> put_req_header("content-type", "audio/mpeg")
          |> put_req_header("x-username", "CustomUser")
          |> post(~p"/api/sounds/play-stream", audio_data)

        assert %{"played_by" => "api-only-user"} = json_response(conn, 200)
      end
    end

    test "uses volume from query params", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer,
        play_url: fn _path, volume, _username ->
          send(self(), {:volume, volume})
          :ok
        end do
        audio_data = <<0xFF, 0xFB, 0x90, 0x00>>

        conn
        |> put_req_header("content-type", "audio/mpeg")
        |> post(~p"/api/sounds/play-stream?volume=0.5", audio_data)

        assert_received {:volume, 0.5}
      end
    end

    test "uses volume from x-volume header when query param not set", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer,
        play_url: fn _path, volume, _username ->
          send(self(), {:volume, volume})
          :ok
        end do
        audio_data = <<0xFF, 0xFB, 0x90, 0x00>>

        conn
        |> put_req_header("content-type", "audio/mpeg")
        |> put_req_header("x-volume", "0.75")
        |> post(~p"/api/sounds/play-stream", audio_data)

        assert_received {:volume, 0.75}
      end
    end

    test "defaults volume to 1.0 for invalid value", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer,
        play_url: fn _path, volume, _username ->
          send(self(), {:volume, volume})
          :ok
        end do
        audio_data = <<0xFF, 0xFB, 0x90, 0x00>>

        conn
        |> put_req_header("content-type", "audio/mpeg")
        |> post(~p"/api/sounds/play-stream?volume=invalid", audio_data)

        assert_received {:volume, 1.0}
      end
    end

    test "detects audio/wav content type", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer,
        play_url: fn path, _volume, _username ->
          send(self(), {:path, path})
          :ok
        end do
        audio_data = "RIFF" <> <<0, 0, 0, 0>> <> "WAVE"

        conn
        |> put_req_header("content-type", "audio/wav")
        |> post(~p"/api/sounds/play-stream", audio_data)

        assert_received {:path, path}
        assert String.ends_with?(path, ".wav")
      end
    end

    test "detects audio/ogg content type", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer,
        play_url: fn path, _volume, _username ->
          send(self(), {:path, path})
          :ok
        end do
        audio_data = "OggS" <> <<0, 0, 0, 0>>

        conn
        |> put_req_header("content-type", "audio/ogg")
        |> post(~p"/api/sounds/play-stream", audio_data)

        assert_received {:path, path}
        assert String.ends_with?(path, ".ogg")
      end
    end

    test "defaults to mp3 extension for unknown content type", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer,
        play_url: fn path, _volume, _username ->
          send(self(), {:path, path})
          :ok
        end do
        audio_data = <<0xFF, 0xFB, 0x90, 0x00>>

        conn
        |> put_req_header("content-type", "application/octet-stream")
        |> post(~p"/api/sounds/play-stream", audio_data)

        assert_received {:path, path}
        assert String.ends_with?(path, ".mp3")
      end
    end

    test "returns unauthorized without valid API token" do
      conn =
        build_conn()
        |> put_req_header("content-type", "audio/mpeg")

      conn = post(conn, ~p"/api/sounds/play-stream", <<0xFF, 0xFB>>)
      assert json_response(conn, 401)
    end
  end

  # Helper functions
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
    tenant = Tenants.ensure_default_tenant!()

    {:ok, tag} =
      %Tag{}
      |> Tag.changeset(%{
        name: "test_tag#{System.unique_integer([:positive])}",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    tag
  end

  defp insert_user do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer([:positive])}",
        discord_id: "#{System.unique_integer([:positive])}",
        avatar: "test_avatar.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    user
  end

  defp insert_sound_tag(sound, tag) do
    {:ok, _} =
      %Soundboard.SoundTag{}
      |> Soundboard.SoundTag.changeset(%{
        sound_id: sound.id,
        tag_id: tag.id,
        tenant_id: sound.tenant_id
      })
      |> Repo.insert()
  end
end
