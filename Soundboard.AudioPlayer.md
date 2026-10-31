# `Soundboard.AudioPlayer`

Facade over the per-guild audio player servers.

One `Soundboard.AudioPlayer.Server` process exists per guild. All functions
route by `guild_id`; when omitted, the default guild is used so existing
single-guild deployments behave exactly as before.

# `current_voice_channel`

# `ensure_started`

```elixir
@spec ensure_started(String.t()) :: pid()
```

Starts the player for `guild_id` if not already running. Returns its pid.

# `invalidate_cache`

# `invalidate_cache`

Removes any cached metadata for `filename` in `guild_id` so future plays use
fresh data. The 1-arity form targets the default guild (back-compat).

# `last_user_left`

# `play_sound`

# `playback_finished`

# `server_pid`

```elixir
@spec server_pid(String.t()) :: pid() | nil
```

Pid of the player server for `guild_id`, if running.

# `set_voice_channel`

# `stop_sound`

# `user_joined_channel`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
