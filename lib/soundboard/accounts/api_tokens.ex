defmodule Soundboard.Accounts.ApiTokens do
  @moduledoc """
  Context for managing API tokens bound to users.
  """
  import Ecto.Query
  alias Soundboard.Repo
  alias Soundboard.Accounts.{ApiToken, User}

  @prefix "sb_"

  def list_tokens(%User{id: user_id}) do
    from(t in ApiToken,
      where: t.user_id == ^user_id and is_nil(t.revoked_at),
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  def generate_token(%User{id: user_id}, attrs \\ %{}) do
    raw = random_token()
    hash = hash_token(raw)

    changeset =
      %ApiToken{}
      |> ApiToken.changeset(%{
        user_id: user_id,
        token_hash: hash,
        token: raw,
        label: Map.get(attrs, "label") || Map.get(attrs, :label)
      })

    case Repo.insert(changeset) do
      {:ok, token} -> {:ok, raw, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def verify_token(raw) when is_binary(raw) do
    query =
      from t in ApiToken,
        where: t.token_hash == ^hash_token(raw) and is_nil(t.revoked_at)

    case Repo.one(query) do
      nil ->
        {:error, :invalid}

      token ->
        token = Repo.preload(token, :user)
        # update last_used_at asynchronously
        _ = update_last_used_at(token)
        {:ok, token.user, token}
    end
  end

  def revoke_token(%User{id: user_id}, token_id) do
    token_id = normalize_id(token_id)

    case Repo.get(ApiToken, token_id) do
      %ApiToken{user_id: ^user_id} = token ->
        token
        |> Ecto.Changeset.change(
          revoked_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        )
        |> Repo.update()

      %ApiToken{} ->
        {:error, :forbidden}

      nil ->
        {:error, :not_found}
    end
  end

  defp update_last_used_at(%ApiToken{} = token) do
    token
    |> Ecto.Changeset.change(
      last_used_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    )
    |> Repo.update()
  end

  defp random_token do
    @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  defp hash_token(raw) do
    :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower)
  end

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> int
      :error -> -1
    end
  end
end
