defmodule Soundboard.Chains.ChainItem do
  @moduledoc """
  Ordered item within a chain.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Soundboard.Chains.Chain
  alias Soundboard.Sound

  schema "chain_items" do
    field :position, :integer

    belongs_to :chain, Chain
    belongs_to :sound, Sound

    timestamps()
  end

  def changeset(chain_item, attrs) do
    chain_item
    |> cast(attrs, [:position, :chain_id, :sound_id])
    |> validate_required([:position, :chain_id, :sound_id])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint(:position, name: :chain_items_chain_id_position_index)
  end
end
