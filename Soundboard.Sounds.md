# `Soundboard.Sounds`

Sound domain context.

# `create_error_message`

```elixir
@spec create_error_message(Ecto.Changeset.t() | String.t() | term()) :: String.t()
```

# `create_sound`

```elixir
@spec create_sound(Soundboard.Sounds.Uploads.CreateRequest.t()) ::
  {:ok, Soundboard.Sound.t()} | {:error, Ecto.Changeset.t()}
```

# `delete_sound`

```elixir
@spec delete_sound(Soundboard.Sound.t(), integer()) :: :ok | {:error, term()}
```

# `fetch_filename_extension`

```elixir
@spec fetch_filename_extension(term()) :: {:ok, String.t()} | :error
```

# `fetch_sound_id`

```elixir
@spec fetch_sound_id(String.t()) :: {:ok, integer()} | :error
```

# `filename_conflicts_across_extensions?`

```elixir
@spec filename_conflicts_across_extensions?(String.t(), [String.t()]) :: boolean()
```

# `filename_taken?`

```elixir
@spec filename_taken?(String.t()) :: boolean()
```

# `filename_taken_excluding?`

```elixir
@spec filename_taken_excluding?(String.t(), integer() | String.t()) :: boolean()
```

# `get_recent_uploads`

```elixir
@spec get_recent_uploads(keyword()) :: [{String.t(), String.t(), NaiveDateTime.t()}]
```

# `get_sound!`

```elixir
@spec get_sound!(term()) :: Soundboard.Sound.t()
```

# `get_user_join_sound`

```elixir
@spec get_user_join_sound(integer()) :: String.t() | nil
```

# `get_user_join_sound_by_discord_id`

```elixir
@spec get_user_join_sound_by_discord_id(term()) :: String.t() | nil
```

# `get_user_leave_sound`

```elixir
@spec get_user_leave_sound(integer()) :: String.t() | nil
```

# `get_user_leave_sound_by_discord_id`

```elixir
@spec get_user_leave_sound_by_discord_id(term()) :: String.t() | nil
```

# `get_user_sound_preferences_by_discord_id`

```elixir
@spec get_user_sound_preferences_by_discord_id(term()) :: map() | nil
```

# `ids_by_filename`

```elixir
@spec ids_by_filename([String.t()]) :: %{optional(String.t()) =&gt; integer()}
```

# `list_detailed`

```elixir
@spec list_detailed() :: [Soundboard.Sound.t()]
```

# `list_files`

```elixir
@spec list_files() :: [Soundboard.Sound.t()]
```

# `new_create_request`

```elixir
@spec new_create_request(Soundboard.Accounts.User.t() | nil, map()) ::
  Soundboard.Sounds.Uploads.CreateRequest.t()
```

# `put_request_upload`

```elixir
@spec put_request_upload(Soundboard.Sounds.Uploads.CreateRequest.t(), map() | nil) ::
  Soundboard.Sounds.Uploads.CreateRequest.t()
```

# `update_sound`

```elixir
@spec update_sound(Soundboard.Sound.t(), map()) ::
  {:ok, Soundboard.Sound.t()} | {:error, Ecto.Changeset.t()}
```

# `update_sound`

```elixir
@spec update_sound(Soundboard.Sound.t(), integer(), map()) ::
  {:ok, Soundboard.Sound.t()} | {:error, term()}
```

# `validate_create`

```elixir
@spec validate_create(Soundboard.Sounds.Uploads.CreateRequest.t()) ::
  {:ok, map()} | {:error, Ecto.Changeset.t()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
