defmodule SoundboardWeb.API.SoundControllerTest do
  @moduledoc """
  The JSON API through the endpoint and router: bearer-token auth, listing,
  favorites, creating sounds (URL and multipart), playing, stopping and
  fetching files, storage plans, and tenant isolation. Only the audio player
  and the Discord cache are mocked.
  """
  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.Accounts.ApiTokens
  alias Soundboard.Favorites.Favorite
  alias Soundboard.{Repo, Sound, Tag, Tenants, UploadsPath, UserSoundSetting}

  setup %{conn: conn} do
    files_before = uploaded_files()

    on_exit(fn ->
      for file <- uploaded_files() -- files_before, do: File.rm(UploadsPath.file_path(file))
    end)

    user = user_fixture()
    tag = Repo.insert!(%Tag{name: "tag#{System.unique_integer([:positive])}"})
    sound = insert_sound!(user, %{tags: [tag]})
    {:ok, raw_token, token} = ApiTokens.generate_token(user, %{label: "API Test"})

    %{
      conn: put_req_header(conn, "authorization", "Bearer " <> raw_token),
      sound: sound,
      tag: tag,
      token: token,
      user: user
    }
  end

  describe "auth" do
    test "refuses a missing, unknown or revoked token", %{conn: conn, user: user, token: token} do
      {:ok, _} = ApiTokens.revoke_token(user, token.id)

      for conn <- [
            build_conn(),
            put_req_header(build_conn(), "authorization", "Bearer sb_unknown"),
            conn
          ] do
        assert conn |> get(~p"/api/sounds") |> json_response(401) == %{
                 "error" => "Invalid API token"
               }
      end
    end

    test "answers 500 when the token's bookkeeping cannot be saved" do
      with_mock ApiTokens, verify_token: fn _ -> {:error, :token_update_failed} end do
        conn =
          build_conn()
          |> put_req_header("authorization", "Bearer anytoken")
          |> get(~p"/api/sounds")

        assert json_response(conn, 500) == %{"error" => "API token verification failed"}
      end
    end
  end

  describe "GET /api/sounds" do
    test "lists the guild's sounds with their tags and the user's join/leave flags", %{
      conn: conn,
      sound: sound,
      tag: tag,
      user: user
    } do
      Repo.insert!(%UserSoundSetting{
        user_id: user.id,
        sound_id: sound.id,
        guild_id: sound.guild_id,
        is_join_sound: true
      })

      insert_sound!(user, %{guild_id: "another-guild"})

      assert [listed] = conn |> get(~p"/api/sounds") |> json_response(200) |> Map.fetch!("data")
      assert listed["id"] == sound.id
      assert listed["filename"] == sound.filename
      assert listed["tags"] == [tag.name]
      assert listed["is_join_sound"] == true
      assert listed["is_leave_sound"] == false
    end
  end

  describe "GET /api/favorites" do
    test "lists the user's favorites in the current guild only", %{
      conn: conn,
      sound: sound,
      user: user
    } do
      elsewhere = insert_sound!(user, %{guild_id: "another-guild"})
      someone_elses = insert_sound!(user_fixture())

      for fav <- [sound, elsewhere],
          do: Repo.insert!(%Favorite{user_id: user.id, sound_id: fav.id})

      Repo.insert!(%Favorite{user_id: user_fixture().id, sound_id: someone_elses.id})

      assert [%{"id" => id}] =
               conn |> get(~p"/api/favorites") |> json_response(200) |> Map.fetch!("data")

      assert id == sound.id
    end
  end

  describe "POST /api/sounds" do
    test "creates a URL sound with tags, volume and a join flag", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "url",
          "name" => "api-url",
          "url" => "https://example.com/wow.mp3",
          "tags" => ["meme", "reaction"],
          "volume" => "35",
          "is_join_sound" => "true"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["filename"] == "api-url.mp3"
      assert data["source_type"] == "url"
      assert data["url"] == "https://example.com/wow.mp3"
      assert data["is_join_sound"] == true

      sound = Repo.preload(Repo.get_by!(Sound, filename: "api-url.mp3"), :tags)
      assert Enum.sort(Enum.map(sound.tags, & &1.name)) == ["meme", "reaction"]
      assert_in_delta sound.volume, 0.35, 0.0001

      setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: sound.id)
      assert setting.is_join_sound
      refute setting.is_leave_sound
    end

    test "files the sound in the request's guild, whatever guild_id the client sends", %{
      conn: conn
    } do
      params = %{"name" => "smuggled", "url" => "https://e.com/a.mp3", "guild_id" => "elsewhere"}

      assert %{"id" => id} =
               conn |> post(~p"/api/sounds", params) |> json_response(201) |> Map.fetch!("data")

      assert Repo.get!(Sound, id).guild_id == Tenants.default_guild_id()
    end

    test "infers the source type from what was sent", %{conn: conn} do
      for {params, source_type, filename} <- [
            {%{"url" => "https://example.com/inferred.mp3"}, "url", "inferred-url.mp3"},
            {%{"url" => "http://example.com"}, "url", "no-path"},
            {%{"file" => fixture_upload("inferred.mp3")}, "local", "inferred-file.mp3"}
          ] do
        name = Path.rootname(filename)
        conn = post(conn, ~p"/api/sounds", Map.put(params, "name", name))

        assert %{"source_type" => ^source_type, "filename" => ^filename} =
                 json_response(conn, 201)["data"]
      end
    end

    test "stores a multipart upload under its storage key", %{conn: conn} do
      conn =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "local",
          "name" => "api-local",
          "file" => fixture_upload("sample.mp3"),
          "tags" => "api,local",
          "volume" => "120",
          "is_leave_sound" => "true"
        })

      assert %{"data" => data} = json_response(conn, 201)
      assert data["filename"] == "api-local.mp3"
      assert data["source_type"] == "local"
      assert data["is_leave_sound"] == true

      sound = Repo.get_by!(Sound, filename: "api-local.mp3")
      assert_in_delta sound.volume, 1.2, 0.0001
      assert sound.byte_size == File.stat!(Soundboard.TestHelpers.audio_fixture_path()).size

      assert File.read!(UploadsPath.file_path(sound.storage_key)) ==
               File.read!(Soundboard.TestHelpers.audio_fixture_path())
    end

    test "a new join or leave sound replaces the user's previous one in that guild", %{
      conn: conn,
      user: user
    } do
      with_mock EDA.Cache, [:passthrough], fetch_member: fn _, _ -> {:ok, %{}} end do
        for guild <- [Tenants.default_guild_id(), "join-guild"],
            flag <- ["is_join_sound", "is_leave_sound"] do
          conn = init_test_session(conn, %{guild_id: guild})
          {:ok, _} = Tenants.get_or_create_guild(guild)

          [first, second] =
            for n <- [1, 2] do
              name = "#{flag}-#{guild}-#{n}"
              params = %{"name" => name, "url" => "https://example.com/#{n}.mp3", flag => "true"}

              assert %{"data" => %{"id" => id}} =
                       conn |> post(~p"/api/sounds", params) |> json_response(201)

              Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: id)
            end

          key = String.to_existing_atom(flag)
          refute Map.fetch!(Repo.reload!(first), key), "#{guild} #{flag}"
          assert Map.fetch!(Repo.reload!(second), key), "#{guild} #{flag}"
        end
      end
    end

    test "names the missing field", %{conn: conn} do
      for {params, field, message} <- [
            {%{"source_type" => "url", "url" => "https://example.com/a.mp3"}, "filename",
             "can't be blank"},
            {%{"source_type" => "url", "name" => "missing-url"}, "url", "can't be blank"},
            {%{"source_type" => "local", "name" => "missing-file"}, "file",
             "Please select a file"}
          ] do
        assert %{"errors" => %{^field => [^message]}} =
                 conn |> post(~p"/api/sounds", params) |> json_response(422)
      end
    end

    test "refuses a name already used in the guild, by URL or by file", %{conn: conn, user: user} do
      insert_sound!(user, %{filename: "dup.mp3"})
      files_before = uploaded_files()

      for params <- [
            %{"url" => "https://example.com/new.mp3"},
            %{"file" => fixture_upload("dup.mp3")}
          ] do
        conn = post(conn, ~p"/api/sounds", Map.put(params, "name", "dup"))

        assert %{"errors" => %{"filename" => ["has already been taken"]}} =
                 json_response(conn, 422)
      end

      assert uploaded_files() == files_before
    end

    test "refuses a file that would go over the guild's storage cap", %{conn: conn} do
      {:ok, _} =
        Tenants.get_or_create_guild(Tenants.default_guild_id(), %{max_storage_bytes: 100})

      files_before = uploaded_files()

      conn =
        post(conn, ~p"/api/sounds", %{"name" => "too-big", "file" => fixture_upload("big.mp3")})

      assert %{"errors" => %{"base" => [message]}} = json_response(conn, 422)
      assert message =~ "Storage limit reached for this soundboard (100 B cap)"
      refute Repo.get_by(Sound, filename: "too-big.mp3")
      assert uploaded_files() == files_before
    end

    test "refuses a URL that is not http or https with a host", %{conn: conn} do
      sounds_before = Repo.aggregate(Sound, :count)

      for url <- [
            "file:///etc/passwd",
            "javascript:alert(1)",
            "ftp://example.com/a.mp3",
            "https://"
          ] do
        conn = post(conn, ~p"/api/sounds", %{"name" => "bad-url", "url" => url})

        assert json_response(conn, 422) == %{
                 "errors" => %{"url" => ["must be an http or https URL"]}
               },
               url
      end

      assert Repo.aggregate(Sound, :count) == sounds_before
    end

    test "refuses a file whose bytes are not audio, whatever its name", %{conn: conn} do
      files_before = uploaded_files()
      path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-fake.mp3")
      File.write!(path, "just some text pretending to be audio")
      on_exit(fn -> File.rm(path) end)
      upload = %Plug.Upload{path: path, filename: "fake.mp3", content_type: "audio/mpeg"}

      conn = post(conn, ~p"/api/sounds", %{"name" => "fake", "file" => upload})

      assert json_response(conn, 422) == %{
               "errors" => %{
                 "file" => ["Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."]
               }
             }

      assert uploaded_files() == files_before
    end

    test "refuses a file given as a server path instead of an upload", %{conn: conn} do
      files_before = uploaded_files()

      conn =
        post(conn, ~p"/api/sounds", %{
          "source_type" => "local",
          "name" => "server-path",
          "file" => %{
            "path" => Soundboard.TestHelpers.audio_fixture_path(),
            "filename" => "x.mp3"
          }
        })

      assert %{"errors" => %{"file" => ["Please select a file"]}} = json_response(conn, 422)
      refute Repo.get_by(Sound, filename: "server-path.mp3")
      assert uploaded_files() == files_before
    end

    test "refuses malformed JSON and bodies over the upload limit", %{conn: conn} do
      sounds_before = Repo.aggregate(Sound, :count)
      json = put_req_header(conn, "content-type", "application/json")
      too_big = :binary.copy("a", Application.fetch_env!(:soundboard, :max_upload_bytes) + 1)

      assert_error_sent 400, fn -> post(json, ~p"/api/sounds", "{") end
      assert_error_sent 413, fn -> post(json, ~p"/api/sounds", too_big) end
      assert Repo.aggregate(Sound, :count) == sounds_before
    end
  end

  describe "POST /api/sounds/:id/play" do
    test "plays the sound as the token's user, whatever x-username says", %{
      conn: conn,
      sound: sound,
      user: user
    } do
      with_mock Soundboard.AudioPlayer, play_sound: fn _filename, _actor, _guild -> :ok end do
        conn =
          conn
          |> put_req_header("x-username", "Impostor")
          |> post(~p"/api/sounds/#{sound.id}/play")

        assert json_response(conn, 202)["data"] == %{
                 "status" => "accepted",
                 "message" => "Playback request accepted for #{sound.filename}",
                 "requested_by" => user.username,
                 "sound" => %{"id" => sound.id, "filename" => sound.filename}
               }

        assert_called(
          Soundboard.AudioPlayer.play_sound(sound.filename, user, Tenants.default_guild_id())
        )
      end
    end

    test "is a 404 for an unknown sound or another guild's sound", %{conn: conn, user: user} do
      elsewhere = insert_sound!(user, %{guild_id: "another-guild"})

      with_mock Soundboard.AudioPlayer, play_sound: fn _, _, _ -> :ok end do
        for id <- [999_999, elsewhere.id] do
          conn = post(conn, ~p"/api/sounds/#{id}/play")
          assert json_response(conn, 404) == %{"error" => "Sound not found"}
        end

        refute called(Soundboard.AudioPlayer.play_sound(:_, :_, :_))
      end
    end
  end

  describe "POST /api/sounds/stop" do
    test "stops playback in the current guild", %{conn: conn} do
      with_mock Soundboard.AudioPlayer, stop_sound: fn _ -> :ok end do
        conn = post(conn, ~p"/api/sounds/stop")

        assert json_response(conn, 202)["data"] == %{
                 "status" => "accepted",
                 "message" => "Stop request accepted"
               }

        assert_called(Soundboard.AudioPlayer.stop_sound(Tenants.default_guild_id()))
      end
    end
  end

  describe "GET /api/sounds/:id/file" do
    test "sends a local sound's stored file", %{conn: conn, user: user} do
      sound = insert_sound!(user)
      File.mkdir_p!(UploadsPath.dir())
      File.write!(UploadsPath.file_path(sound.storage_key), "the audio")
      on_exit(fn -> File.rm(UploadsPath.file_path(sound.storage_key)) end)

      assert conn |> get(~p"/api/sounds/#{sound.id}/file") |> response(200) == "the audio"
    end

    test "redirects to a URL sound's source", %{conn: conn, user: user} do
      sound =
        insert_sound!(user, %{source_type: "url", url: "https://cdn.example.com/a.mp3"})

      assert conn |> get(~p"/api/sounds/#{sound.id}/file") |> redirected_to() ==
               "https://cdn.example.com/a.mp3"
    end

    test "is a 404 when the file is gone, the sound is unknown or in another guild", %{
      conn: conn,
      sound: sound,
      user: user
    } do
      elsewhere = insert_sound!(user, %{guild_id: "another-guild"})

      for {id, error} <- [
            {sound.id, "Sound file missing"},
            {999_999, "Sound not found"},
            {elsewhere.id, "Sound not found"}
          ] do
        assert conn |> get(~p"/api/sounds/#{id}/file") |> json_response(404) == %{
                 "error" => error
               }
      end
    end
  end

  describe "storage plans" do
    setup %{conn: conn, user: user} do
      enable_billing()

      deliver_stripe_event(%{
        "id" => "evt_plan_#{System.unique_integer([:positive])}",
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "customer" => "cus_plan",
            "metadata" => %{
              "guild_id" => "plan-guild",
              "price_id" => "price_pro_m",
              "owner_discord_id" => user.discord_id
            }
          }
        }
      })

      %{conn: init_test_session(conn, %{guild_id: "plan-guild"})}
    end

    setup_with_mocks([{EDA.Cache, [:passthrough], fetch_member: fn _, _ -> {:ok, %{}} end}]) do
      :ok
    end

    test "a cancelled subscription can no longer add sounds", %{conn: conn} do
      files_before = uploaded_files()

      deliver_stripe_event(%{
        "id" => "evt_plan_deleted",
        "type" => "customer.subscription.deleted",
        "data" => %{
          "object" => %{"status" => "canceled", "metadata" => %{"guild_id" => "plan-guild"}}
        }
      })

      for params <- [
            %{"name" => "after-cancel-url", "url" => "https://example.com/a.mp3"},
            %{"name" => "after-cancel-file", "file" => fixture_upload("after.mp3")}
          ] do
        conn = post(conn, ~p"/api/sounds", params)

        assert %{"errors" => %{"base" => [message]}} = json_response(conn, 422)
        assert message =~ "no active plan"
      end

      refute Repo.get_by(Sound, guild_id: "plan-guild")
      assert uploaded_files() == files_before
    end
  end

  describe "tenant isolation" do
    setup %{user: user} do
      Application.put_env(:soundboard, :tenant_base_host, "soundbored.app")
      on_exit(fn -> Application.delete_env(:soundboard, :tenant_base_host) end)

      {:ok, _} = Tenants.get_or_create_guild("guild-b", %{slug: "b-slug"})
      %{b_sound: insert_sound!(user, %{guild_id: "guild-b"})}
    end

    test "a token whose user is not in the subdomain's guild is refused everywhere", %{
      conn: conn,
      b_sound: b_sound
    } do
      conn = %{conn | host: "b-slug.soundbored.app"}

      with_mocks([
        {EDA.Cache, [:passthrough], fetch_member: fn _guild, _user -> {:error, :not_found} end},
        {Soundboard.AudioPlayer, [],
         play_sound: fn _, _, _ -> :ok end, stop_sound: fn _ -> :ok end}
      ]) do
        requests = [
          get(conn, ~p"/api/sounds"),
          get(conn, ~p"/api/favorites"),
          post(conn, ~p"/api/sounds/#{b_sound.id}/play"),
          get(conn, ~p"/api/sounds/#{b_sound.id}/file"),
          post(conn, ~p"/api/sounds/stop"),
          post(conn, ~p"/api/sounds", %{"name" => "planted", "url" => "https://example.com/x.mp3"})
        ]

        for response <- requests, do: assert(response.status == 403)
        refute Repo.get_by(Sound, filename: "planted.mp3")
        refute called(Soundboard.AudioPlayer.play_sound(:_, :_, :_))
        refute called(Soundboard.AudioPlayer.stop_sound(:_))
      end
    end

    test "a member's token works on the subdomain and sees only that guild", %{
      conn: conn,
      b_sound: b_sound
    } do
      with_mock EDA.Cache, [:passthrough], fetch_member: fn "guild-b", _user -> {:ok, %{}} end do
        conn = get(%{conn | host: "b-slug.soundbored.app"}, ~p"/api/sounds")

        assert [%{"id" => id}] = json_response(conn, 200)["data"]
        assert id == b_sound.id
      end
    end
  end

  defp insert_sound!(user, attrs \\ %{}) do
    %Sound{}
    |> Sound.changeset(
      Map.merge(
        %{
          filename: "sound#{System.unique_integer([:positive])}.mp3",
          source_type: "local",
          user_id: user.id
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp fixture_upload(filename) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{filename}")
    File.cp!(Soundboard.TestHelpers.audio_fixture_path(), path)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: filename, content_type: "audio/mpeg"}
  end

  defp uploaded_files do
    File.mkdir_p!(UploadsPath.dir())
    File.ls!(UploadsPath.dir())
  end
end
