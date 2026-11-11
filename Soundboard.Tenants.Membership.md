# `Soundboard.Tenants.Membership`

Who may use and who may manage a guild's soundboard.

A user may use a guild's soundboard only while they are a member of that
Discord guild. The deployment's default guild (`Tenants.default_guild_id/0`)
is open to every signed-in user, so self-hosted installs keep working with
no configuration (the role check already gates who signs in there).

Membership is read from Discord through `EDA.Cache.fetch_member/2`: the
gateway's member cache first, the REST API on a miss. When Discord cannot
be reached the answer is no.

# `member?`

```elixir
@spec member?(String.t() | term(), String.t() | nil) :: boolean()
```

# `owner?`

```elixir
@spec owner?(String.t() | term(), String.t() | nil) :: boolean()
```

Whether the user may manage the guild (claim its slug, run its billing):
only the owner recorded when it was provisioned. A guild with no recorded
owner is manageable only when it is the default guild.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
