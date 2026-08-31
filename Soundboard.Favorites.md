# `Soundboard.Favorites`

The Favorites module.

# `favorite_result`

```elixir
@type favorite_result() ::
  {:ok, Soundboard.Favorites.Favorite.t()} | {:error, Ecto.Changeset.t()}
```

# `error_message`

```elixir
@spec error_message(Ecto.Changeset.t()) :: String.t()
```

# `favorite?`

```elixir
@spec favorite?(integer(), integer()) :: boolean()
```

# `list_favorite_sounds_with_tags`

```elixir
@spec list_favorite_sounds_with_tags(integer()) :: [Soundboard.Sound.t()]
```

# `list_favorites`

```elixir
@spec list_favorites(integer()) :: [integer()]
```

# `max_favorites`

```elixir
@spec max_favorites() :: pos_integer()
```

# `toggle_favorite`

```elixir
@spec toggle_favorite(integer(), integer()) :: favorite_result()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
