defmodule Soundboard.Favorites.Favorite do
  @moduledoc """
  The Favorite module.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Soundboard.Accounts.User
  alias Soundboard.Sound

  schema "favorites" do
    belongs_to :user, User
    belongs_to :sound, Sound

    timestamps()
  end

  def changeset(favorite, attrs) do
    favorite
    |> cast(attrs, [:user_id, :sound_id])
    |> validate_required([:user_id, :sound_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:sound_id)
    |> unique_constraint([:user_id, :sound_id])
  end
end
