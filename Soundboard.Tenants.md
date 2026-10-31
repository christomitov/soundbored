# `Soundboard.Tenants`

Multi-tenant context.

A tenant is a Discord guild with a provisioned soundboard: a row in the
`guilds` table plus a slug that maps to `{slug}.soundbored.app`.

Backward compatibility: every guild-scoped operation falls back to
`default_guild_id/0` when no guild is given, so existing single-guild
deployments behave identically with zero configuration.

# `bot_guilds`

```elixir
@spec bot_guilds() :: [
  %{
    id: String.t(),
    name: String.t() | nil,
    guild: Soundboard.Tenants.Guild.t() | nil
  }
]
```

Lists the guilds the shared Discord bot is a member of, with their tenant
rows (if claimed). Used by the guild switcher and onboarding.

# `claim_slug`

```elixir
@spec claim_slug(String.t() | term(), String.t()) ::
  {:ok, Soundboard.Tenants.Guild.t()}
  | {:error, :slug_taken | :invalid_slug | Ecto.Changeset.t()}
```

Claims `{slug}` for the given Discord guild, creating the tenant row if
needed. Returns `{:error, :slug_taken}` / `{:error, :invalid_slug}` /
`{:error, changeset}`.

# `default_guild_id`

```elixir
@spec default_guild_id() :: String.t()
```

The guild used when no tenant is specified.

Resolution order: `SOUNDBOARD_DEFAULT_GUILD_ID` env (configured as
`:default_guild_id`), the existing `DISCORD_REQUIRED_GUILD_ID` env
(configured as `:required_guild_id`), the bot's sole guild (discovered via
`GuildCache` for zero-config single-guild deployments that never set the
legacy envs), then the literal `"default"`.

# `get_by_slug`

```elixir
@spec get_by_slug(String.t()) :: Soundboard.Tenants.Guild.t() | nil
```

# `get_guild`

```elixir
@spec get_guild(String.t() | term()) :: Soundboard.Tenants.Guild.t() | nil
```

# `get_or_create_guild`

```elixir
@spec get_or_create_guild(String.t() | term(), map()) ::
  {:ok, Soundboard.Tenants.Guild.t()} | {:error, term()}
```

# `list_guilds`

```elixir
@spec list_guilds() :: [Soundboard.Tenants.Guild.t()]
```

# `put_default_guild_id`

```elixir
@spec put_default_guild_id(Ecto.Changeset.t()) :: Ecto.Changeset.t()
```

Changeset helper: defaults a blank `guild_id` to the default guild, so
pre-tenant call sites and single-guild deployments keep working unchanged.

# `reconcile_default_guild`

```elixir
@spec reconcile_default_guild() :: :skipped | {:ok, non_neg_integer()}
```

One-time self-heal for deployments upgrading from pre-multi-tenant code that
never configured a guild env (see `default_guild_id/0`).

When no env is configured and the bot is in exactly one guild, that guild is
the deployment's guild. The migration backfills the literal `"default"`;
this repoints those rows to the real guild id so web queries and voice
playbacks line up after upgrading.

Guarded: no-ops when a guild env is configured (those deployments backfill
correctly at migration time) or when the bot is in zero/many guilds (then an
explicit identity — env or slug claim — is required). Idempotent.

# `reserved_slugs`

# `scope_guild_id`

```elixir
@spec scope_guild_id(String.t() | nil) :: String.t()
```

The guild id to scope by: the given id, or the default guild.

# `slug_available?`

```elixir
@spec slug_available?(String.t()) :: boolean()
```

Whether a slug can be claimed (valid format, not reserved, not taken).

# `storage_cap`

```elixir
@spec storage_cap(String.t() | term()) :: pos_integer() | nil
```

The storage cap for a guild: its own `max_storage_bytes`, or nil when the
guild has no cap — which means unlimited. Caps exist only where subscriptions
put them: on hosted, the billing webhook writes exact plan caps; self-hosted
installs have no cap at all.

# `storage_remaining`

```elixir
@spec storage_remaining(String.t() | term()) :: non_neg_integer() | nil
```

# `storage_used`

```elixir
@spec storage_used(String.t() | term()) :: non_neg_integer()
```

Bytes of uploaded storage used by a guild. Sounds with unknown size
(`byte_size = 0`, e.g. rows created before guild scoping) count as zero, so
existing deployments are never retroactively blocked by a cap.

# `within_storage_limit?`

```elixir
@spec within_storage_limit?(String.t() | term(), non_neg_integer()) :: boolean()
```

Whether uploading `incoming_bytes` more would stay within the guild's cap.
An uncapped guild (self-hosted) is always within its limit.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
