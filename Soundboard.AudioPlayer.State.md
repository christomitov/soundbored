# `Soundboard.AudioPlayer.State`

The state of a per-guild audio player server.

# `t`

```elixir
@type t() :: %Soundboard.AudioPlayer.State{
  current_playback: map() | nil,
  guild_id: String.t(),
  idle_timeout_ref: {reference(), reference()} | nil,
  interrupt_watchdog_attempt: non_neg_integer() | nil,
  interrupt_watchdog_ref: reference() | nil,
  interrupting: boolean() | nil,
  pending_request: map() | nil,
  voice_channel: {String.t(), String.t()} | nil
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
