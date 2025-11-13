defmodule Soundboard.Accounts.User do
  @moduledoc """
  The User module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.Tenant

  schema "users" do
    field :discord_id, :string
    field :username, :string
    field :avatar, :string
    belongs_to :tenant, Tenant

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:discord_id, :username, :avatar, :tenant_id])
    |> validate_required([:discord_id, :username, :tenant_id])
    |> assoc_constraint(:tenant)
    |> unique_constraint(:discord_id,
      name: :users_tenant_id_discord_id_index
    )
  end
end
