defmodule Soundboard.Accounts.ApiToken do
  @moduledoc """
  API access token bound to a user. Stores only a SHA-256 hash of the token.
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Soundboard.Accounts.{Tenant, User}
  alias Soundboard.Repo

  schema "api_tokens" do
    belongs_to :user, User
    belongs_to :tenant, Tenant
    field :token_hash, :string
    field :token, :string
    field :label, :string
    field :revoked_at, :naive_datetime
    field :last_used_at, :naive_datetime

    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :tenant_id, :token_hash, :token, :label, :revoked_at, :last_used_at])
    |> ensure_tenant_from_user()
    |> validate_required([:user_id, :tenant_id, :token_hash])
    |> unique_constraint(:token_hash)
    |> assoc_constraint(:user)
    |> assoc_constraint(:tenant)
  end

  defp ensure_tenant_from_user(changeset) do
    case get_field(changeset, :tenant_id) do
      nil ->
        case get_field(changeset, :user_id) do
          nil ->
            changeset

          user_id ->
            case Repo.get(User, user_id) do
              %User{tenant_id: tid} when not is_nil(tid) ->
                put_change(changeset, :tenant_id, tid)

              _ ->
                changeset
            end
        end

      _ ->
        changeset
    end
  end
end
