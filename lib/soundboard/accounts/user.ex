defmodule Soundboard.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

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
