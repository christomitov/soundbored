defmodule SoundboardWeb.Plugs.TenantTest do
  @moduledoc """
  Tenant resolution through the router: subdomain, then session, then the
  default guild, with unknown subdomains rejected before any controller and
  guilds the user is not a member of refused or dropped.
  """

  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.Accounts.ApiTokens
  alias Soundboard.Tenants

  setup_with_mocks([
    {EDA.Cache, [:passthrough],
     guilds: fn -> [] end,
     fetch_member: fn
       "333", _ -> {:error, :not_found}
       _, _ -> {:ok, %{}}
     end}
  ]) do
    :ok
  end

  setup %{conn: conn} do
    {:ok, _} = Tenants.get_or_create_guild("111", %{slug: "acme", name: "Acme"})
    {:ok, _} = Tenants.get_or_create_guild("222", %{slug: "other"})
    {:ok, _} = Tenants.get_or_create_guild("333", %{slug: "closed"})
    %{conn: sign_in(conn, user_fixture())}
  end

  test "with no tenant host configured, every host is the default guild", %{conn: conn} do
    conn = get(%{conn | host: "acme.soundbored.app"}, "/guilds")

    assert conn.assigns.current_guild_id == Tenants.default_guild_id()
  end

  describe "with a tenant base host" do
    setup do
      Application.put_env(:soundboard, :tenant_base_host, "soundbored.app")
      on_exit(fn -> Application.delete_env(:soundboard, :tenant_base_host) end)
    end

    test "a subdomain picks its guild, and the session remembers it for LiveViews", %{
      conn: conn
    } do
      conn = get(%{conn | host: "acme.soundbored.app"}, "/guilds")

      assert conn.assigns.current_guild_id == "111"
      assert get_session(conn, :guild_id) == "111"
    end

    test "on the apex host the session's guild applies, else the default", %{conn: conn} do
      apex = %{conn | host: "soundbored.app"}

      assert get(apex, "/guilds").assigns.current_guild_id == Tenants.default_guild_id()

      assert apex
             |> init_test_session(%{guild_id: "222"})
             |> get("/guilds")
             |> Map.get(:assigns)
             |> Map.get(:current_guild_id) ==
               "222"
    end

    test "an unknown subdomain is a 404 before any controller runs" do
      {:ok, raw, _} = ApiTokens.generate_token(user_fixture())

      conn =
        %{build_conn() | host: "nope.soundbored.app"}
        |> put_req_header("authorization", "Bearer " <> raw)
        |> get("/api/sounds")

      assert response(conn, 404) == "Unknown soundboard"
    end

    test "a subdomain whose guild the user is not in is a 403", %{conn: conn} do
      conn = get(%{conn | host: "closed.soundbored.app"}, "/guilds")

      assert response(conn, 403) == "You are not a member of this soundboard"
    end

    test "a session guild the user is not in falls back to the default guild", %{conn: conn} do
      conn = conn |> init_test_session(%{guild_id: "333"}) |> get("/guilds")

      assert conn.assigns.current_guild_id == Tenants.default_guild_id()
      assert get_session(conn, :guild_id) == Tenants.default_guild_id()
    end
  end
end
