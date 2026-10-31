# `Soundboard.Discord.InviteURL`

Builds the bot invite URL used by the onboarding flow.

The shared bot only needs to see the channels it is invited to, connect to
voice, and speak. The permissions integer is pinned by a test in
`SoundboardWeb.OnboardingTest` so the scope cannot drift silently.

# `build`

```elixir
@spec build(String.t() | nil) :: String.t()
```

# `permissions`

```elixir
@spec permissions() :: non_neg_integer()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
