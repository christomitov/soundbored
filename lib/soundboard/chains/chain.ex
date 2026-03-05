defmodule Soundboard.Chains.Chain do
  @moduledoc """
  Chain schema storing an ordered list of sounds per user.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Soundboard.Accounts.User
  alias Soundboard.Chains.ChainItem

  schema "chains" do
    field :name, :string
    field :is_public, :boolean, default: false

    belongs_to :user, User
    has_many :chain_items, ChainItem, on_delete: :delete_all

    timestamps()
  end

  def changeset(chain, attrs) do
    chain
    |> cast(attrs, [:name, :is_public, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint(:name, name: :chains_user_id_name_index)
  end
end
