defmodule Soundboard.Stats.Play do
  @moduledoc """
  The Play module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.User

  schema "plays" do
    field :sound_name, :string
    belongs_to :user, User

    timestamps()
  end

  def changeset(play, attrs) do
    play
    |> cast(attrs, [:sound_name, :user_id])
    |> validate_required([:sound_name, :user_id])
  end
end
