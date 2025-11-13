defmodule Soundboard.Accounts.ApiTokensTest do
  use Soundboard.DataCase
  alias Soundboard.Repo
  alias Soundboard.Accounts.{ApiTokens, Tenants, User}

  setup do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "apitok_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    %{user: user, tenant: tenant}
  end

  test "generate, verify, revoke token lifecycle", %{user: user} do
    {:ok, raw, token_rec} = ApiTokens.generate_token(user, %{label: "CI"})
    assert is_binary(raw) and String.starts_with?(raw, "sb_")
    assert token_rec.user_id == user.id
    assert token_rec.token == raw
    assert token_rec.token_hash != nil
    assert token_rec.tenant_id == user.tenant_id

    # verify returns user and updates last_used_at
    assert {:ok, ^user, verified_token} = ApiTokens.verify_token(raw)
    # Reload to ensure last_used_at persisted
    reloaded = Repo.get(Soundboard.Accounts.ApiToken, verified_token.id)
    assert reloaded.last_used_at != nil

    # list_tokens includes it while active
    assert [listed] = ApiTokens.list_tokens(user)
    assert listed.id == token_rec.id
    assert listed.tenant_id == user.tenant_id

    # revoke and ensure it's hidden and cannot verify
    assert {:ok, _} = ApiTokens.revoke_token(user, token_rec.id)
    assert [] == ApiTokens.list_tokens(user)
    assert {:error, :invalid} == ApiTokens.verify_token(raw)
  end

  test "verify_token returns error for invalid token", %{user: _user} do
    # ensure user created to avoid false positives
    assert {:error, :invalid} == ApiTokens.verify_token("sb_invalid_token")
  end

  test "revoke_token forbids other users", %{user: user} do
    {:ok, _raw, token} = ApiTokens.generate_token(user, %{label: "owner"})

    {:ok, other} =
      %User{}
      |> User.changeset(%{
        username: "apitok_other_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive]) + 1),
        avatar: "a.jpg",
        tenant_id: Tenants.ensure_default_tenant!().id
      })
      |> Repo.insert()

    assert {:error, :forbidden} == ApiTokens.revoke_token(other, token.id)
  end

  test "list_tokens empty for new user and revoke not_found on unknown id" do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "apitok_empty_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive]) + 2),
        avatar: "b.jpg",
        tenant_id: Tenants.ensure_default_tenant!().id
      })
      |> Repo.insert()

    assert [] == ApiTokens.list_tokens(user)
    # Passing string id should be normalized but not found
    assert {:error, :not_found} == ApiTokens.revoke_token(user, "999999")
    # Passing invalid string normalizes to -1 and should still be not_found
    assert {:error, :not_found} == ApiTokens.revoke_token(user, "not_an_int")
  end
end
