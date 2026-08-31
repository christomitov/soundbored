# `Soundboard.Sounds.Uploads`

Canonical sound upload/create API.

# `create_error`

```elixir
@type create_error() :: Ecto.Changeset.t()
```

# `create_result`

```elixir
@type create_result() :: {:ok, Soundboard.Sound.t()} | {:error, create_error()}
```

# `create`

```elixir
@spec create(Soundboard.Sounds.Uploads.CreateRequest.t()) :: create_result()
```

# `error_message`

```elixir
@spec error_message(Ecto.Changeset.t() | String.t() | term()) :: String.t()
```

# `validate`

```elixir
@spec validate(Soundboard.Sounds.Uploads.CreateRequest.t()) ::
  {:ok, map()} | {:error, Ecto.Changeset.t()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
