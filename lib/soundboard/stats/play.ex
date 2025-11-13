defmodule Soundboard.Stats.Play do
  @moduledoc """
  The Play module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.{Tenant, User}

  schema "plays" do
    field :sound_name, :string
    belongs_to :user, User
    belongs_to :tenant, Tenant

    timestamps()
  end

  def changeset(play, attrs) do
    play
    |> cast(attrs, [:sound_name, :user_id, :tenant_id])
    |> validate_required([:sound_name, :user_id, :tenant_id])
    |> assoc_constraint(:tenant)
  end
end
