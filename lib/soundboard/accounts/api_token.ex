defmodule Soundboard.Accounts.ApiToken do
  @moduledoc """
  API access token bound to a user.

  The token hash is used for verification. The plaintext token is also persisted
  so the Settings UI can display and copy active tokens after creation.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.User

  @type t :: %__MODULE__{
          id: integer() | nil,
          user_id: integer() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil,
          token_hash: String.t() | nil,
          token: String.t() | nil,
          label: String.t() | nil,
          revoked_at: NaiveDateTime.t() | nil,
          last_used_at: NaiveDateTime.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

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
