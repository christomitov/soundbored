# `Soundboard.Accounts.ApiToken`

API access token bound to a user.

The token hash is used for verification. The plaintext token is shown once
at creation time and is never persisted.

# `t`

```elixir
@type t() :: %Soundboard.Accounts.ApiToken{
  __meta__: term(),
  id: integer() | nil,
  inserted_at: NaiveDateTime.t() | nil,
  label: String.t() | nil,
  last_used_at: NaiveDateTime.t() | nil,
  revoked_at: NaiveDateTime.t() | nil,
  token_hash: String.t() | nil,
  updated_at: NaiveDateTime.t() | nil,
  user: Soundboard.Accounts.User.t() | Ecto.Association.NotLoaded.t() | nil,
  user_id: integer() | nil
}
```

# `changeset`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
