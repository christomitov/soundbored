# `Soundboard.Accounts.ApiTokens`

Context for managing API tokens bound to users.

# `revoke_result`

```elixir
@type revoke_result() ::
  {:ok, Soundboard.Accounts.ApiToken.t()}
  | {:error, :forbidden | :not_found | Ecto.Changeset.t()}
```

# `verify_error`

```elixir
@type verify_error() :: :invalid | :token_update_failed
```

# `verify_result`

```elixir
@type verify_result() ::
  {:ok, Soundboard.Accounts.User.t(), Soundboard.Accounts.ApiToken.t()}
  | {:error, verify_error()}
```

# `generate_token`

```elixir
@spec generate_token(Soundboard.Accounts.User.t(), map()) ::
  {:ok, String.t(), Soundboard.Accounts.ApiToken.t()}
  | {:error, Ecto.Changeset.t()}
```

# `list_tokens`

```elixir
@spec list_tokens(Soundboard.Accounts.User.t()) :: [Soundboard.Accounts.ApiToken.t()]
```

# `revoke_token`

```elixir
@spec revoke_token(Soundboard.Accounts.User.t(), integer() | String.t()) ::
  revoke_result()
```

# `verify_token`

```elixir
@spec verify_token(String.t()) :: verify_result()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
