defmodule Soundboard.Accounts.ApiTokensTest do
  use Soundboard.DataCase, async: false

  import Mock

  alias Soundboard.Accounts.{ApiToken, ApiTokens, User}
  alias Soundboard.Repo

  setup do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "apitok_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg"
      })
      |> Repo.insert()

    %{user: user}
  end

  test "generate, verify, revoke token lifecycle", %{user: user} do
    {:ok, raw, token_rec} = ApiTokens.generate_token(user, %{label: "CI"})
    assert String.starts_with?(raw, "sb_")
    assert token_rec.user_id == user.id
    assert token_rec.token_hash != nil

    assert {:ok, ^user, verified_token} = ApiTokens.verify_token(raw)
    reloaded = Repo.get(Soundboard.Accounts.ApiToken, verified_token.id)
    assert reloaded.last_used_at != nil

    assert [listed] = ApiTokens.list_tokens(user)
    assert listed.id == token_rec.id

    assert {:ok, _} = ApiTokens.revoke_token(user, token_rec.id)
    assert [] == ApiTokens.list_tokens(user)
    assert {:error, :invalid} == ApiTokens.verify_token(raw)
  end

  test "verify_token returns error for invalid token", %{user: _user} do
    assert {:error, :invalid} == ApiTokens.verify_token("sb_invalid_token")
  end

  test "verify_token returns error when last_used_at update fails", %{user: user} do
    {:ok, raw, token} = ApiTokens.generate_token(user, %{label: "failing-update"})

    stored_token = Repo.get!(ApiToken, token.id)
    preloaded_token = Repo.preload(stored_token, :user)
    failed_changeset = Ecto.Changeset.change(stored_token)

    with_mock Soundboard.Repo,
      one: fn _query -> stored_token end,
      preload: fn ^stored_token, :user -> preloaded_token end,
      update: fn _changeset -> {:error, failed_changeset} end do
      assert {:error, :token_update_failed} == ApiTokens.verify_token(raw)
    end
  end

  test "revoke_token forbids other users", %{user: user} do
    {:ok, _raw, token} = ApiTokens.generate_token(user, %{label: "owner"})

    {:ok, other} =
      %User{}
      |> User.changeset(%{
        username: "apitok_other_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive]) + 1),
        avatar: "a.jpg"
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
        avatar: "b.jpg"
      })
      |> Repo.insert()

    assert [] == ApiTokens.list_tokens(user)
    assert {:error, :not_found} == ApiTokens.revoke_token(user, "999999")
    assert {:error, :not_found} == ApiTokens.revoke_token(user, "not_an_int")
  end

  test "revoke_token rejects partially parsed string ids", %{user: user} do
    {:ok, _raw, token} = ApiTokens.generate_token(user, %{label: "strict-id"})

    assert {:error, :not_found} == ApiTokens.revoke_token(user, "#{token.id}garbage")

    assert [listed] = ApiTokens.list_tokens(user)
    assert listed.id == token.id
  end
end
