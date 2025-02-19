defmodule Soundboard.Tag do
  @moduledoc """
  The Tag module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "tags" do
    field :name, :string
    many_to_many :sounds, Soundboard.Sound, join_through: "sound_tags"

    timestamps()
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def search(query \\ __MODULE__, search_term) do
    from t in query,
      where: like(fragment("lower(?)", t.name), ^"%#{String.downcase(search_term)}%"),
      order_by: t.name,
      limit: 10
  end
end
