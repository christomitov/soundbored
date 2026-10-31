# `Soundboard.AudioPlayer.Server`

Per-guild audio playback coordinator.

One Server process exists per guild that has audio activity, registered in
`Soundboard.AudioPlayer.Registry` under the guild id and supervised by
`Soundboard.AudioPlayer.Supervisor`. All state (voice channel, queue,
playback) is scoped to a single guild, so multiple tenants cannot interfere
with each other.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

# `via`

```elixir
@spec via(String.t()) ::
  {:via, Registry, {Soundboard.AudioPlayer.Registry, String.t()}}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
