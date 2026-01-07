defmodule Soundboard.Accounts.Tenant do
  @moduledoc """
  Tenant record representing an isolated customer/installation boundary.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tenants" do
    field :name, :string
    field :slug, :string
    field :plan, Ecto.Enum, values: [:community, :pro], default: :community
    field :max_sounds, :integer
    field :max_users, :integer
    field :max_guilds, :integer
    field :billing_customer_id, :string
    field :billing_subscription_id, :string
    field :subscription_ends_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :name,
      :slug,
      :plan,
      :max_sounds,
      :max_users,
      :max_guilds,
      :billing_customer_id,
      :billing_subscription_id,
      :subscription_ends_at
    ])
    |> validate_required([:name, :slug, :plan])
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> unique_constraint(:slug)
  end
end
