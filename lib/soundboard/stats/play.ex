defmodule Soundboard.Stats.Play do
  @moduledoc """
  The Play module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.User
  alias Soundboard.Sound

  schema "plays" do
    field :sound_name, :string
    belongs_to :sound, Sound
    belongs_to :user, User

    timestamps()
  end

  def changeset(play, attrs) do
    play
    |> cast(attrs, [:sound_name, :sound_id, :user_id])
    |> validate_required([:sound_name, :user_id])
    |> assoc_constraint(:sound)
  end
end
