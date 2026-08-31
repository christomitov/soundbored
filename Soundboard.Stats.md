# `Soundboard.Stats`

Handles the stats of the soundboard.

# `leaderboard_entry`

```elixir
@type leaderboard_entry() :: {String.t(), non_neg_integer()}
```

# `recent_play_entry`

```elixir
@type recent_play_entry() :: {integer(), String.t(), String.t(), NaiveDateTime.t()}
```

# `broadcast_stats_update`

```elixir
@spec broadcast_stats_update() :: :ok | {:error, term()}
```

# `get_recent_plays`

```elixir
@spec get_recent_plays(keyword()) :: [recent_play_entry()]
```

# `get_top_sounds`

```elixir
@spec get_top_sounds(Date.t(), Date.t(), keyword()) :: [leaderboard_entry()]
```

# `get_top_users`

```elixir
@spec get_top_users(Date.t(), Date.t(), keyword()) :: [leaderboard_entry()]
```

# `reset_weekly_stats`

```elixir
@spec reset_weekly_stats() :: :ok | {:error, term()}
```

# `track_play`

```elixir
@spec track_play(String.t(), integer() | nil) ::
  {:ok, Soundboard.Stats.Play.t()} | {:error, Ecto.Changeset.t()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
