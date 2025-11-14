defmodule Soundboard.AccountsTest do
  use Soundboard.DataCase, async: true

  alias Soundboard.Accounts
  alias Soundboard.Accounts.{Tenant, User}
  alias Soundboard.Repo
  alias Soundboard.Sound

  test "can_create_sound?/1 respects tenant limits" do
    tenant = insert_tenant(%{max_sounds: 1})
    user = insert_user(tenant)

    assert Accounts.can_create_sound?(tenant)

    %Sound{}
    |> Sound.changeset(%{filename: "limit.mp3", user_id: user.id, tenant_id: tenant.id})
    |> Repo.insert!()

    reloaded = Repo.get!(Tenant, tenant.id)
    refute Accounts.can_create_sound?(reloaded)
  end

  test "plan_usage returns counts and limit metadata" do
    tenant = insert_tenant(%{max_sounds: 2, max_users: 3, max_guilds: 4})
    user = insert_user(tenant)

    %Sound{}
    |> Sound.changeset(%{filename: "usage.mp3", user_id: user.id, tenant_id: tenant.id})
    |> Repo.insert!()

    usage = Accounts.plan_usage(Repo.get!(Tenant, tenant.id))
    assert usage.sounds.count == 1
    assert usage.sounds.limit == 2
    refute usage.sounds.at_limit?
  end

  test "apply_billing_update normalizes webhook payloads" do
    tenant = insert_tenant(%{})
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    {:ok, updated} =
      Accounts.apply_billing_update(tenant, %{
        "plan" => "pro",
        "billing_customer_id" => "cust_123",
        "billing_subscription_id" => "sub_456",
        "subscription_ends_at" => timestamp
      })

    assert updated.plan == :pro
    assert updated.billing_customer_id == "cust_123"
    assert updated.billing_subscription_id == "sub_456"
    assert updated.subscription_ends_at
  end

  defp insert_tenant(attrs) do
    slug = "tenant-#{System.unique_integer([:positive])}"

    {:ok, tenant} =
      %Tenant{}
      |> Tenant.changeset(
        Map.merge(%{name: "Tenant #{slug}", slug: slug, plan: :community}, attrs)
      )
      |> Repo.insert()

    tenant
  end

  defp insert_user(tenant) do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "user-#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    user
  end
end
