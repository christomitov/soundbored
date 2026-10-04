defmodule Soundboard.Tenants.Guild do
  @moduledoc """
  A tenant: one Discord guild's provisioned soundboard.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "guilds" do
    field :discord_guild_id, :string
    field :slug, :string
    field :name, :string
    field :max_storage_bytes, :integer
    field :owner_discord_id, :string

    timestamps()
  end

  @doc false
  def changeset(guild, attrs) do
    guild
    |> cast(attrs, [:discord_guild_id, :slug, :name, :max_storage_bytes, :owner_discord_id])
    |> validate_required([:discord_guild_id])
    |> validate_slug()
    |> unique_constraint(:discord_guild_id)
    |> unique_constraint(:slug)
  end

  defp validate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        changeset

      _slug ->
        changeset
        |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$/,
          message: "must be lowercase letters, digits, and dashes (max 30 chars)"
        )
        |> validate_exclusion(:slug, Soundboard.Tenants.reserved_slugs(), message: "is reserved")
    end
  end
end
