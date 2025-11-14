defmodule Soundboard.Accounts.GuildsTest do
  use Soundboard.DataCase, async: false

  alias Soundboard.Accounts.{Guilds, Tenant, Tenants}
  alias Soundboard.Repo

  test "associate_guild creates a mapping" do
    tenant = Tenants.ensure_default_tenant!()

    assert {:ok, guild} = Guilds.associate_guild(tenant, "12345")
    assert guild.discord_guild_id == "12345"

    assert {:ok, resolved} = Guilds.get_tenant_for_guild("12345")
    assert resolved.id == tenant.id
  end

  test "associate_guild updates when mapping exists" do
    default = Tenants.ensure_default_tenant!()

    slug = "guild-update-#{System.unique_integer([:positive])}"

    {:ok, other_tenant} =
      %Tenant{}
      |> Tenant.changeset(%{name: "Other", slug: slug, plan: :pro})
      |> Repo.insert()

    assert {:ok, _} = Guilds.associate_guild(default, "999")
    assert {:ok, current} = Guilds.get_tenant_for_guild("999")
    assert current.id == default.id

    assert {:ok, _} = Guilds.associate_guild(other_tenant, "999")
    assert {:ok, updated} = Guilds.get_tenant_for_guild("999")
    assert updated.id == other_tenant.id
  end

  test "associate_guild enforces tenant guild limit" do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, limited} =
      tenant
      |> Tenant.changeset(%{max_guilds: 1})
      |> Repo.update()

    assert {:ok, _} = Guilds.associate_guild(limited, "10001")
    assert {:error, :guild_limit} = Guilds.associate_guild(limited, "10002")
  end

  test "get_tenant_for_guild returns error when missing" do
    assert {:error, :not_found} = Guilds.get_tenant_for_guild("does-not-exist")
  end
end
