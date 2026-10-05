defmodule SoundboardWeb.Plugs.TenantTest do
  @moduledoc """
  Behavioral tests for tenant resolution: subdomain → session → default guild,
  with unknown subdomains rejected. With no tenant host configured (the
  single-guild case), every request resolves to the default guild.
  """

  use SoundboardWeb.ConnCase, async: false

  alias Soundboard.Tenants

  setup do
    {:ok, _} = Tenants.get_or_create_guild("111", %{slug: "acme", name: "Acme"})
    :ok
  end

  describe "without a tenant base host configured (single-guild default)" do
    test "resolves to the default guild", %{conn: conn} do
      conn = dispatch(conn, "soundbored.local")

      assert conn.assigns.current_guild_id == Tenants.default_guild_id()
    end
  end

  describe "with a tenant base host configured" do
    setup do
      Application.put_env(:soundboard, :tenant_base_host, "soundbored.app")

      on_exit(fn ->
        Application.delete_env(:soundboard, :tenant_base_host)
      end)

      :ok
    end

    test "subdomain slug resolves to that guild's tenant", %{conn: conn} do
      conn = dispatch(conn, "acme.soundbored.app")

      assert conn.assigns.current_guild_id == "111"
      assert conn.assigns.current_guild.slug == "acme"
    end

    test "unknown subdomain is rejected with 404", %{conn: conn} do
      conn = dispatch(conn, "nope.soundbored.app")

      assert conn.status == 404
      assert conn.halted
    end

    test "the apex host falls through to session/default resolution", %{conn: conn} do
      conn = dispatch(conn, "soundbored.app")

      assert conn.assigns.current_guild_id == Tenants.default_guild_id()
    end

    test "session guild wins when no subdomain is present", %{conn: conn} do
      Tenants.get_or_create_guild("222", %{slug: "other"})
      conn = Plug.Test.init_test_session(conn, %{"guild_id" => "222"})

      conn = dispatch(conn, "soundbored.app")

      assert conn.assigns.current_guild_id == "222"
    end

    test "resolved guild id is mirrored into the session for LiveViews", %{conn: conn} do
      conn = dispatch(conn, "acme.soundbored.app")

      assert get_session(conn, "guild_id") == "111"
    end
  end

  defp dispatch(conn, host) do
    conn = Plug.Test.init_test_session(conn, %{})

    conn
    |> assign(:current_user, nil)
    |> Map.replace!(:host, host)
    |> SoundboardWeb.Plugs.Tenant.call(SoundboardWeb.Plugs.Tenant.init([]))
    |> case do
      %{halted: true} = conn -> conn
      conn -> Plug.Conn.send_resp(conn, 200, "")
    end
    |> maybe_wait_resp()
  end

  defp maybe_wait_resp(%{state: :sent} = conn), do: conn
  defp maybe_wait_resp(conn), do: conn
end
