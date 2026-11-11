# `Soundboard.TableOwner`

Owns the app's shared ETS tables (billing's processed events, Stripe
customers and subscriptions, and the sound metadata cache).

An ETS table dies with the process that created it. Webhooks and billing
pages run in short-lived request processes, and audio players stop when
idle, so tables are created by this supervised process instead and live as
long as the application.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `ensure_tables`

```elixir
@spec ensure_tables([atom()]) :: :ok
```

Makes sure every table in `tables` exists, owned by this process.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
