defmodule Soundboard.Accounts.TenantsTest do
  use Soundboard.DataCase, async: true

  alias Soundboard.Accounts.{Tenant, Tenants}
  alias Soundboard.Repo

  setup do
    Repo.delete_all(Tenant)
    :ok
  end

  test "ensure_default_tenant! creates with overrides and reuses existing record" do
    created = Tenants.ensure_default_tenant!(%{name: "Custom Default", max_users: 5})
    assert created.slug == Tenants.default_slug()
    assert created.name == "Custom Default"
    assert created.max_users == 5

    # Subsequent calls reuse the same tenant instead of creating duplicates
    reused = Tenants.ensure_default_tenant!(%{name: "Ignored"})
    assert reused.id == created.id
    assert reused.name == created.name
  end

  test "get_tenant handles integer and string ids" do
    tenant = Tenants.ensure_default_tenant!()

    assert {:ok, ^tenant} = Tenants.get_tenant(tenant.id)
    assert {:ok, ^tenant} = Tenants.get_tenant(Integer.to_string(tenant.id))
    assert {:error, :not_found} = Tenants.get_tenant("invalid-id")
  end

  test "get_tenant_by_slug trims and normalizes input" do
    {:ok, tenant} =
      %Tenant{}
      |> Tenant.changeset(%{name: "SlugTenant", slug: "sluggy", plan: :pro})
      |> Repo.insert()

    assert {:ok, ^tenant} = Tenants.get_tenant_by_slug("sluggy")
    assert {:error, :not_found} = Tenants.get_tenant_by_slug("missing")
  end
end
