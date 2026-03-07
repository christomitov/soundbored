defmodule Soundboard.Stats.Play do
  @moduledoc """
  The Play module.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Soundboard.Accounts.User
  alias Soundboard.Sound

  schema "plays" do
    field :played_filename, :string
    belongs_to :sound, Sound
    belongs_to :user, User

    timestamps()
  end

  def changeset(play, attrs) do
    play
    |> cast(attrs, [:played_filename, :sound_id, :user_id])
    |> validate_required([:played_filename, :sound_id, :user_id])
    |> assoc_constraint(:sound)
  end
end
