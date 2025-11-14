defmodule SoundboardWeb.APIAuthDBTokenTest do
  use SoundboardWeb.ConnCase
  import Phoenix.ConnTest
  import Mock
  alias Soundboard.{Repo, Sound}
  alias Soundboard.Accounts.{ApiTokens, Tenant, Tenants, User}

  setup %{conn: conn} do
    # Ensure legacy token does not interfere
    System.delete_env("API_TOKEN")

    tenant = Tenants.ensure_default_tenant!()

    other_tenant =
      %Tenant{}
      |> Tenant.changeset(%{name: "Other Tenant", slug: "other", plan: :pro})
      |> Repo.insert!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "apitok_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg",
        tenant_id: tenant.id
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

    {:ok, other_user} =
      %User{}
      |> User.changeset(%{
        username: "other_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "other.jpg",
        tenant_id: other_tenant.id
      })
      |> Repo.insert()

    {:ok, other_sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "other_sound_#{System.unique_integer([:positive])}.mp3",
        source_type: "local",
        user_id: other_user.id
      })
      |> Repo.insert()

    conn = put_req_header(conn, "authorization", "Bearer " <> raw)

    %{
      conn: conn,
      user: user,
      sound: sound,
      other_sound: other_sound
    }
  end

  test "GET /api/sounds scopes by tenant", %{conn: conn, sound: sound, other_sound: other_sound} do
    conn = get(conn, ~p"/api/sounds")
    assert %{"data" => data} = json_response(conn, 200)
    assert Enum.any?(data, &(&1["id"] == sound.id))
    refute Enum.any?(data, &(&1["id"] == other_sound.id))
  end

  test "POST /api/sounds/:id/play authorized via DB token", %{conn: conn, sound: sound} do
    # Mock the audio player so we don't actually attempt voice playback
    with_mock SoundboardWeb.AudioPlayer, play_sound: fn _, _ -> :ok end do
      conn = post(conn, ~p"/api/sounds/#{sound.id}/play")
      assert %{"status" => "success"} = json_response(conn, 200)
    end
  end

  test "POST /api/sounds/:id/play blocks other tenant sounds", %{
    conn: conn,
    other_sound: other_sound
  } do
    conn = post(conn, ~p"/api/sounds/#{other_sound.id}/play")
    assert %{"error" => "Sound not found"} = json_response(conn, 404)
  end

  test "POST /api/sounds/stop authorized via DB token", %{conn: conn} do
    with_mock SoundboardWeb.AudioPlayer, stop_sound: fn -> :ok end do
      conn = post(conn, ~p"/api/sounds/stop")
      assert %{"status" => "success"} = json_response(conn, 200)
    end
  end

  test "unauthorized when token invalid", %{conn: _conn} do
    conn = build_conn() |> put_req_header("authorization", "Bearer badtoken")
    conn = get(conn, ~p"/api/sounds")
    assert json_response(conn, 401)
  end
end
