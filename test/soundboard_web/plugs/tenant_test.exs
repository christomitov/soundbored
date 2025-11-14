defmodule SoundboardWeb.Plugs.TenantTest do
  use SoundboardWeb.ConnCase, async: true

  alias Plug.Test
  alias Soundboard.Accounts.{Tenant, Tenants}
  alias Soundboard.Repo

  setup do
    original = Application.get_env(:soundboard, :edition, :community)

    on_exit(fn ->
      Application.put_env(:soundboard, :edition, original)
    end)

    :ok
  end

  test "assigns the default tenant in community mode", %{conn: conn} do
    Application.put_env(:soundboard, :edition, :community)
    tenant = Tenants.ensure_default_tenant!()

    conn =
      conn
      |> Test.init_test_session(%{})
      |> SoundboardWeb.Plugs.Tenant.call(%{})

    assert conn.assigns.current_tenant.id == tenant.id
    assert conn.assigns.edition == :community
    assert get_session(conn, :tenant_id) == tenant.id
  end

  test "resolves tenant from subdomain in pro mode", %{conn: conn} do
    Application.put_env(:soundboard, :edition, :pro)

    {:ok, tenant} =
      %Tenant{}
      |> Tenant.changeset(%{name: "Acme", slug: "acme", plan: :pro})
      |> Repo.insert()

    conn =
      conn
      |> Map.put(:host, "acme.localhost")
      |> Test.init_test_session(%{})
      |> SoundboardWeb.Plugs.Tenant.call(%{})

    assert conn.assigns.current_tenant.id == tenant.id
    assert conn.assigns.edition == :pro
    assert get_session(conn, :tenant_id) == tenant.id
  end
end
