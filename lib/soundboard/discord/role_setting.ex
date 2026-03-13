defmodule Soundboard.Discord.RoleSetting do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          guild_id: String.t() | nil,
          role_id: String.t() | nil,
          cooldown_ms: integer() | nil,
          can_upload: boolean() | nil,
          can_play: boolean() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "discord_role_settings" do
    field :guild_id, :string
    field :role_id, :string
    field :cooldown_ms, :integer, default: 0
    field :can_upload, :boolean, default: true
    field :can_play, :boolean, default: true

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(role_setting, attrs) do
    role_setting
    |> cast(attrs, [:guild_id, :role_id, :cooldown_ms, :can_upload, :can_play])
    |> validate_required([:guild_id, :role_id, :cooldown_ms, :can_upload, :can_play])
    |> validate_number(:cooldown_ms, greater_than_or_equal_to: 0)
    |> unique_constraint([:guild_id, :role_id])
  end
end
