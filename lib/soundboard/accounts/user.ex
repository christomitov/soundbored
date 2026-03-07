defmodule Soundboard.Accounts.User do
  @moduledoc """
  The User module.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          discord_id: String.t() | nil,
          username: String.t() | nil,
          avatar: String.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "users" do
    field :discord_id, :string
    field :username, :string
    field :avatar, :string

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:discord_id, :username, :avatar])
    |> validate_required([:discord_id, :username])
    |> unique_constraint(:discord_id)
  end
end
