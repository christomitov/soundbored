defmodule SoundboardWeb.APIAuthDBTokenTest do
  use SoundboardWeb.ConnCase
  import Phoenix.ConnTest
  import Mock

  alias Soundboard.{Repo, Sound}
  alias Soundboard.Accounts.{ApiTokens, User}

  setup %{conn: conn} do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "apitok_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg"
      })
      |> Repo.insert()

    {:ok, raw, _rec} = ApiTokens.generate_token(user, %{label: "test"})

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test_sound_#{System.unique_integer([:positive])}.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert()

    conn = put_req_header(conn, "authorization", "Bearer " <> raw)
    %{conn: conn, user: user, sound: sound}
  end

  test "GET /api/sounds authorized via DB token", %{conn: conn} do
    conn = get(conn, ~p"/api/sounds")
    assert json_response(conn, 200)["data"] |> is_list()
  end

  test "POST /api/sounds/:id/play authorized via DB token", %{
    conn: conn,
    sound: sound,
    user: user
  } do
    actor = %{display_name: user.username, user_id: user.id}

    # Mock the audio player so we don't actually attempt voice playback
    with_mock Soundboard.AudioPlayer, play_sound: fn _, _ -> :ok end do
      conn = post(conn, ~p"/api/sounds/#{sound.id}/play")

      assert %{
               "data" => %{
                 "status" => "accepted",
                 "sound" => %{"id" => sound_id, "filename" => filename}
               }
             } = json_response(conn, 202)

      assert sound_id == sound.id
      assert filename == sound.filename
      assert_called(Soundboard.AudioPlayer.play_sound(sound.filename, actor))
    end
  end

  test "POST /api/sounds/stop authorized via DB token", %{conn: conn} do
    with_mock Soundboard.AudioPlayer, stop_sound: fn -> :ok end do
      conn = post(conn, ~p"/api/sounds/stop")
      assert %{"data" => %{"status" => "accepted"}} = json_response(conn, 202)
    end
  end

  test "unauthorized when token invalid", %{conn: _conn} do
    conn = build_conn() |> put_req_header("authorization", "Bearer badtoken")
    conn = get(conn, ~p"/api/sounds")
    assert json_response(conn, 401)
  end

  test "returns internal server error when token bookkeeping fails", %{conn: _conn} do
    with_mock Soundboard.Accounts.ApiTokens,
      verify_token: fn _ -> {:error, :token_update_failed} end do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer anytoken")
        |> get(~p"/api/sounds")

      assert %{"error" => "API token verification failed"} = json_response(conn, 500)
    end
  end
end
