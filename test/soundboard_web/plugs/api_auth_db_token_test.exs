defmodule SoundboardWeb.APIAuthDBTokenTest do
  use SoundboardWeb.ConnCase
  import Phoenix.ConnTest
  import Mock
  alias Soundboard.{Repo, Sound}
  alias Soundboard.Accounts.{ApiTokens, Tenant, Tenants, User}

  setup %{conn: conn} do
    original = Application.get_env(:soundboard, :edition, :community)

    on_exit(fn ->
      Application.put_env(:soundboard, :edition, original)
    end)

    Application.put_env(:soundboard, :edition, :community)
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

    {:ok, other_user} =
      %User{}
      |> User.changeset(%{
        username: "other_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "other.jpg",
        tenant_id: other_tenant.id
      })
      |> Repo.insert()

    {:ok, raw, _rec} = ApiTokens.generate_token(user, %{label: "test"})
    {:ok, other_raw, _rec} = ApiTokens.generate_token(other_user, %{label: "other"})

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test_sound_#{System.unique_integer([:positive])}.mp3",
        source_type: "local",
        user_id: user.id
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
      other_sound: other_sound,
      other_tenant: other_tenant,
      other_raw_token: other_raw,
      raw_token: raw
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
    with_mock SoundboardWeb.AudioPlayer, stop_sound: fn _tenant_id -> :ok end do
      conn = post(conn, ~p"/api/sounds/stop")
      assert %{"status" => "success"} = json_response(conn, 200)
    end
  end

  test "rejects pro token when tenant param mismatches token tenant", %{
    conn: conn,
    other_tenant: other_tenant
  } do
    Application.put_env(:soundboard, :edition, :pro)

    conn = get(conn, ~p"/api/sounds?tenant=#{other_tenant.slug}")
    assert json_response(conn, 401)
  end

  test "clears session when pro token tenant mismatches resolved tenant", %{
    conn: conn,
    other_tenant: other_tenant,
    user: user
  } do
    Application.put_env(:soundboard, :edition, :pro)

    conn =
      conn
      |> init_test_session(%{user_id: user.id, tenant_id: user.tenant_id})
      |> get(~p"/api/sounds?tenant=#{other_tenant.slug}")

    assert json_response(conn, 401)
    assert get_session(conn, :user_id) == nil
    assert get_session(conn, :tenant_id) == nil
    assert conn.assigns[:current_user] == nil
    assert conn.assigns[:api_token] == nil
  end

  test "allows pro token to set tenant when none resolved", %{
    other_raw_token: other_raw_token,
    other_sound: other_sound,
    sound: sound
  } do
    Application.put_env(:soundboard, :edition, :pro)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> other_raw_token)
      |> get(~p"/api/sounds")

    assert %{"data" => data} = json_response(conn, 200)
    assert Enum.any?(data, &(&1["id"] == other_sound.id))
    refute Enum.any?(data, &(&1["id"] == sound.id))
  end

  test "unauthorized when token invalid", %{conn: _conn} do
    conn = build_conn() |> put_req_header("authorization", "Bearer badtoken")
    conn = get(conn, ~p"/api/sounds")
    assert json_response(conn, 401)
  end
end
