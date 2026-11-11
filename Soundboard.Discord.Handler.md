# `Soundboard.Discord.Handler`

Handles the Discord events.

A deployment with no guild configured (no `:default_guild_id` or
`:required_guild_id`) discovers its guild once READY arrives: guilds stream
into the cache after READY, so it polls briefly for the bot's sole guild and
repoints rows migrated as "default" (`Tenants.reconcile_default_guild/0`).

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `dispatch_event`

# `handle_event`

# `init`

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
