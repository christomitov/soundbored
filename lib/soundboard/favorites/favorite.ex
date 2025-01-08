defmodule Soundboard.Favorites.Favorite do
  use Ecto.Schema
  import Ecto.Changeset

  schema "favorites" do
    belongs_to :user, Soundboard.Accounts.User
    field :sound_id, :integer

    timestamps()
  end

  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:user_id, :sound_id])
    |> validate_required([:user_id, :sound_id])
    |> unique_constraint([:user_id, :sound_id])
  end
end
