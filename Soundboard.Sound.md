# `Soundboard.Sound`

Sound schema.

# `t`

```elixir
@type t() :: %Soundboard.Sound{
  __meta__: term(),
  description: term(),
  filename: term(),
  id: term(),
  inserted_at: term(),
  source_type: term(),
  storage_key: term(),
  tags: term(),
  updated_at: term(),
  url: term(),
  user: term(),
  user_id: term(),
  user_sound_settings: term(),
  volume: term()
}
```

# `by_tag`

```elixir
@spec by_tag(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
```

# `changeset`

```elixir
@spec changeset(t(), map()) :: Ecto.Changeset.t()
```

# `with_tags`

```elixir
@spec with_tags(Ecto.Queryable.t()) :: Ecto.Query.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
