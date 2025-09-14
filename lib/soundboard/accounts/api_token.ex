defmodule Soundboard.Accounts.ApiToken do
  @moduledoc """
  API access token bound to a user. Stores only a SHA-256 hash of the token.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.User

  schema "api_tokens" do
    belongs_to :user, User
    field :token_hash, :string
    field :token, :string
    field :label, :string
    field :revoked_at, :naive_datetime
    field :last_used_at, :naive_datetime

    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :token_hash, :token, :label, :revoked_at, :last_used_at])
    |> validate_required([:user_id, :token_hash])
    |> unique_constraint(:token_hash)
    |> assoc_constraint(:user)
  end
end
