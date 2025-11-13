defmodule Soundboard.Accounts.Tenants do
  @moduledoc """
  Helper functions for working with tenant records.
  """
  import Ecto.Query, only: [from: 2]
  alias Soundboard.Repo
  alias Soundboard.Accounts.Tenant

  @default_slug "default"

  def list_tenants do
    Repo.all(from t in Tenant, order_by: [asc: t.inserted_at])
  end

  def get_tenant_by_slug(slug) when is_binary(slug) do
    case Repo.get_by(Tenant, slug: slug) do
      nil -> {:error, :not_found}
      tenant -> {:ok, tenant}
    end
  end

  def get_default_tenant! do
    Repo.get_by!(Tenant, slug: @default_slug)
  end

  def ensure_default_tenant!(attrs \\ %{}) do
    Repo.get_by(Tenant, slug: @default_slug) ||
      %Tenant{}
      |> Tenant.changeset(
        Map.merge(
          %{
            name: Map.get(attrs, :name, "Default Tenant"),
            slug: @default_slug,
            plan: :community
          },
          Map.take(attrs, [
            :max_sounds,
            :max_users,
            :max_guilds,
            :billing_customer_id,
            :billing_subscription_id,
            :subscription_ends_at
          ])
        )
      )
      |> Repo.insert!()
  end

  def default_slug, do: @default_slug
end
