# `Soundboard.Accounts.User`

The User module.

# `t`

```elixir
@type t() :: %Soundboard.Accounts.User{
  __meta__: term(),
  avatar: String.t() | nil,
  discord_id: String.t() | nil,
  id: integer() | nil,
  inserted_at: NaiveDateTime.t() | nil,
  updated_at: NaiveDateTime.t() | nil,
  username: String.t() | nil
}
```

# `changeset`

# `discord_params`

```elixir
@spec discord_params(String.t(), String.t(), String.t() | nil) :: %{
  discord_id: String.t(),
  username: String.t(),
  avatar: String.t() | nil
}
```

The params `changeset/2` accepts from a Discord identity.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
