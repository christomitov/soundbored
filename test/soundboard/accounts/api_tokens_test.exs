defmodule Soundboard.Accounts.ApiTokensTest do
  use Soundboard.DataCase, async: false

  alias Soundboard.Accounts.{ApiToken, ApiTokens, User}
  alias Soundboard.Repo

  test "a token is shown once, stored only as its hash, verifies until revoked" do
    user = Repo.insert!(%User{discord_id: "tok-1", username: "token-owner"})

    {:ok, raw, token_rec} = ApiTokens.generate_token(user, %{label: "CI"})
    assert String.starts_with?(raw, "sb_")

    stored = Repo.get!(ApiToken, token_rec.id)
    assert stored.token_hash == Base.encode16(:crypto.hash(:sha256, raw), case: :lower)
    assert stored.label == "CI"

    assert {:ok, ^user, verified} = ApiTokens.verify_token(raw)
    assert Repo.get!(ApiToken, verified.id).last_used_at

    assert [%ApiToken{id: id}] = ApiTokens.list_tokens(user)
    assert id == token_rec.id

    assert {:ok, _} = ApiTokens.revoke_token(user, token_rec.id)
    assert [] == ApiTokens.list_tokens(user)
    assert {:error, :invalid} == ApiTokens.verify_token(raw)
  end
end
