defmodule SoundboardWeb.Plugs.TenantTest do
  use SoundboardWeb.ConnCase, async: false

  import ExUnit.CaptureLog
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

  test "resolves tenant from path params before session in pro mode", %{conn: conn} do
    Application.put_env(:soundboard, :edition, :pro)

    default = Tenants.ensure_default_tenant!()

    {:ok, tenant} =
      %Tenant{}
      |> Tenant.changeset(%{name: "Acme", slug: "acme", plan: :pro})
      |> Repo.insert()

    conn =
      conn
      |> Map.put(:path_params, %{"tenant_slug" => tenant.slug})
      |> Test.init_test_session(%{tenant_id: default.id})
      |> SoundboardWeb.Plugs.Tenant.call(%{})

    assert conn.assigns.current_tenant.id == tenant.id
    assert conn.assigns.edition == :pro
    assert get_session(conn, :tenant_id) == tenant.id
    assert conn.assigns.tenant_resolution_source == :path
  end

  test "resolves tenant from query params when no path slug", %{conn: conn} do
    Application.put_env(:soundboard, :edition, :pro)
    Tenants.ensure_default_tenant!()

    {:ok, tenant} =
      %Tenant{}
      |> Tenant.changeset(%{name: "Query Tenant", slug: "query-slug", plan: :pro})
      |> Repo.insert()

    conn =
      conn
      |> Map.put(:params, %{"tenant" => tenant.slug})
      |> Map.put(:path_params, %{})
      |> Test.init_test_session(%{})
      |> SoundboardWeb.Plugs.Tenant.call(%{})

    assert conn.assigns.current_tenant.id == tenant.id
    assert get_session(conn, :tenant_id) == tenant.id
    assert conn.assigns.tenant_resolution_source == :query
  end

  test "reuses session tenant without warnings when no params", %{conn: conn} do
    Application.put_env(:soundboard, :edition, :pro)

    {:ok, tenant} =
      %Tenant{}
      |> Tenant.changeset(%{name: "Session Tenant", slug: "session-tenant", plan: :pro})
      |> Repo.insert()

    log =
      capture_log(fn ->
        conn
        |> Test.init_test_session(%{tenant_id: tenant.id})
        |> SoundboardWeb.Plugs.Tenant.call(%{})
        |> then(fn conn ->
          assert conn.assigns.current_tenant.id == tenant.id
          assert conn.assigns.tenant_resolution_source == :session
        end)
      end)

    assert log == ""
  end

  test "falls back to default tenant with warning on invalid slug", %{conn: conn} do
    Application.put_env(:soundboard, :edition, :pro)
    default = Tenants.ensure_default_tenant!()

    log =
      capture_log(fn ->
        conn
        |> Map.put(:params, %{"tenant" => "!!bad"})
        |> Map.put(:path_params, %{})
        |> Test.init_test_session(%{})
        |> SoundboardWeb.Plugs.Tenant.call(%{})
        |> then(fn conn ->
          assert conn.assigns.current_tenant.id == default.id
          assert conn.assigns.tenant_resolution_source == :default
          assert conn.assigns.tenant_resolution_reason == {:invalid_slug, "!!bad", :query}
          assert get_session(conn, :tenant_id) == default.id
        end)
      end)

    assert log =~ "invalid query tenant slug"
    refute log =~ "host"
  end

  test "defaults once with a single missing-tenant warning and persists session", %{conn: conn} do
    Application.put_env(:soundboard, :edition, :pro)
    default = Tenants.ensure_default_tenant!()

    message = "no tenant params or session present; using default tenant"

    log =
      capture_log(fn ->
        conn
        |> Map.put(:params, %{})
        |> Map.put(:path_params, %{})
        |> Test.init_test_session(%{})
        |> SoundboardWeb.Plugs.Tenant.call(%{})
        |> then(fn conn ->
          assert conn.assigns.current_tenant.id == default.id
          assert conn.assigns.tenant_resolution_source == :default
          assert conn.assigns.tenant_resolution_reason == :missing
          assert get_session(conn, :tenant_id) == default.id
        end)
      end)

    assert String.contains?(log, message)
    assert length(String.split(log, message)) == 2
  end

  test "query tenant overrides session tenant", %{conn: conn} do
    Application.put_env(:soundboard, :edition, :pro)
    default = Tenants.ensure_default_tenant!()

    {:ok, tenant} =
      %Tenant{}
      |> Tenant.changeset(%{name: "Query Tenant", slug: "query-overrides", plan: :pro})
      |> Repo.insert()

    conn =
      conn
      |> Map.put(:params, %{"tenant" => tenant.slug})
      |> Map.put(:path_params, %{})
      |> Test.init_test_session(%{tenant_id: default.id})
      |> SoundboardWeb.Plugs.Tenant.call(%{})

    assert conn.assigns.current_tenant.id == tenant.id
    assert conn.assigns.tenant_resolution_source == :query
    assert get_session(conn, :tenant_id) == tenant.id
  end
end
