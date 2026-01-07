defmodule Soundboard.Accounts.Guild do
  @moduledoc """
  Maps a Discord guild (server) to a tenant.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.Tenant

  schema "guilds" do
    field :discord_guild_id, :string
    belongs_to :tenant, Tenant

    timestamps()
  end

  def changeset(guild, attrs) do
    guild
    |> cast(attrs, [:discord_guild_id, :tenant_id])
    |> validate_required([:discord_guild_id, :tenant_id])
    |> validate_format(:discord_guild_id, ~r/^\d+$/)
    |> unique_constraint(:discord_guild_id)
    |> assoc_constraint(:tenant)
  end
end
