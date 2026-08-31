# Multi-Tenant Shared Bot Implementation Plan

**Status:** Implemented on `feature/multi-tenant` (Tasks 1–4 + web tenancy; wildcard routing config via `TENANT_BASE_HOST`)

## Production upgrade path (verified by migration test)

`mix ecto.migrate` on an existing deployment is additive and data-preserving:
`guilds` table created; `sounds.guild_id`/`byte_size` and
`user_sound_settings.guild_id` added and backfilled (existing sounds → default
guild, `byte_size 0` so caps never block retroactively); unique filename index
swapped to per-guild. Rollback (`down`) is data-preserving (filename index
becomes non-unique). See
`test/soundboard/migrations/data_migrations_test.exs` ("guild scoping
migration backfills existing data into the default guild and rolls back").

## Quality gate

Full VibeKit suite adopted (`mix ci` = compile --warnings-as-errors, format
check, test, credo --strict, dialyzer, ex_dna --max-clones 0, reach.check).
387 tests passing, zero warnings.

## Verified design decisions (exploration complete)

- **EDA voice is already per-guild** (`EDA.Voice.Registry` + `DynamicSupervisor`, sessions keyed `{:session, guild_id}`) — simultaneous multi-guild voice works below our code. Only `Soundboard.AudioPlayer` (singleton GenServer) needs the per-guild refactor.
- **Backward compatibility mechanism:** every guild-scoped function takes optional `guild_id` defaulting to `Tenants.default_guild_id()` (env chain: `SOUNDBOARD_DEFAULT_GUILD_ID` → `DISCORD_REQUIRED_GUILD_ID` → `"default"`). Zero-config single-guild deployments behave identically; migration backfills existing sounds into the default guild.
- **Storage stays flat** (UUID storage keys) — guild scoping in DB only; no file moves.
- **Storage caps:** `sounds.byte_size` recorded at upload; guild usage = `SUM(byte_size)`; cap per `guilds.max_storage_bytes`, default from `SOUNDBOARD_DEFAULT_STORAGE_BYTES` (fallback 2GB). Over-cap uploads rejected pre-commit via the changeset error flow. Existing rows backfilled `byte_size = 0` so nobody gets blocked retroactively. Per-guild cap override = the paid-tier knob.
- **Defaults chosen (pending user confirmation):** free cap 2GB; role gating stays global env for v1; stats stay deployment-wide for v1; single branch.
- Playback PubSub topic per guild (default guild keeps existing topic name); LiveViews subscribe to their tenant's topic.
- Tenant resolution plug: subdomain slug → session → default guild; unknown subdomain 404s. Onboarding/portal UI lives in soundbored-app; soundboard app gets minimal claim/switch endpoint backed by `GuildCache`.
**Related:** `../soundbored-app/` (marketing site + future onboarding portal)

**Goal:** Turn Soundbored from one-deployment-per-Discord-server into a single
multi-tenant deployment: ONE hosted bot instance serves many guilds, sounds are
scoped per guild, and users onboard by inviting the shared bot — no per-user bot
tokens, no per-user Docker containers.

**Why:** Discord has no API to create bots on a user's behalf, and one bot token
cannot run in multiple processes. Hosting one shared bot that users invite into
their servers is the only true one-click onboarding, and it collapses the infra
model to a single deployment.

**Constraint:** Every PR below leaves `main` shippable as the existing
single-guild deployment. Multi-guild behavior is enabled incrementally.

---

## Current-state gaps (verified in code)

| Gap | Location |
|---|---|
| `AudioPlayer` is a singleton GenServer holding a single `voice_channel: {guild_id, channel_id}` — one voice connection app-wide | `lib/soundboard/audio_player.ex` |
| `Sound` schema has no `guild_id`; library is global per deployment | `lib/soundboard/sound.ex` |
| Web layer (LiveViews, uploads, auth) assumes one tenant | `lib/soundboard_web/` |

What already works for multi-guild: `Discord.Handler`/`Consumer` are event-driven
and guild-keyed; `GuildCache` is keyed per guild; `DISCORD_REQUIRED_GUILD_ID` is
optional.

---

## Tasks

### Task 1: Guild-scoped data model ☐
- Add `guild_id` (string, snowflake) to `sounds` and `user_sound_settings`.
- Replace unique index `sounds_filename_index` with composite `(guild_id, filename)` (and same for `storage_key`).
- Backfill migration: existing rows get guild from new env `SOUNDBOARD_DEFAULT_GUILD_ID` (falls back to `DISCORD_REQUIRED_GUILD_ID`).
- Scope `Sounds` context queries by guild_id; per-guild uploads path under `priv/static/uploads/{guild_id}/`.
- Uploads volume layout change is additive; existing files migrate via the backfill script.

### Task 2: Per-guild audio playback ☐
- Replace singleton `AudioPlayer` with `DynamicSupervisor` + `Registry` (`Soundboard.AudioPlayer.Supervisor`), one player process per guild, started on demand.
- Public API becomes guild-explicit: `AudioPlayer.play(guild_id, sound_name, actor)`, `set_voice_channel/3`, etc. Update all call sites (`Discord.Handler`, `SoundboardLive`, `Soundboard.Voice` consumers).
- Port auto-join / idle-leave / queue / watchdog behavior per guild (see `docs/specs/voice-auto-join-idle-leave.md`).
- Single-guild deployments behave identically to today.

### Task 3: Multi-guild web tenancy ☐
- Add Discord OAuth `guilds` scope; on login, list the user's guilds where the shared bot is present (cross-check `GuildCache`), require `Manage Server` permission for admin actions.
- Tenant resolution: session stores active `guild_id`; default to the user's only guild, otherwise show a picker.
- Scope `SoundboardLive`, `FavoritesLive`, `SettingsLive`, `StatsLive`, and `UploadController` to the active guild.
- Role gating (`RoleChecker`) becomes per-guild config stored in DB instead of a single global env pair.

### Task 4: Tenants table + onboarding ☐
- New `guilds` table (id, discord_guild_id, slug, subdomain, settings, plan/status) — provisioning a soundboard = inserting a row.
- Onboarding flow in the web app: sign in → pick a guild the bot is in → claim slug/subdomain → done.
- `DISCORD_REQUIRED_GUILD_ID`/`ROLE_IDS` envs become seed data only; runtime gating reads the `guilds` table.
- Slug uniqueness + reservation (reserved: `www`, `dash`, `api`, `admin`).

### Task 5: Routing + deploy as multi-tenant host ☐
- Wildcard host support: `{slug}.soundbored.app` → same app, host header resolves tenant (Caddy on-demand TLS + `A` record `*.soundbored.app`). Path fallback `/s/{slug}` for local dev.
- Single-container deploy config: `PHX_HOST=soundbored.app`, shared bot token, no per-tenant env.
- `RuntimeCapability.discord_handler_enabled?/0` stays — bot still runs in the same BEAM as the web app.

---

## Out of scope for ../soundboard/ (tracked in soundbored-app)

- Onboarding portal / dashboard UI polish, Stripe billing, analytics — belongs in the marketing-site repo or a thin control-plane app that talks to the same DB.
- DNS/Caddy/VPS setup — infra, not code.

## Ship order

PRs land in task order; 1 and 2 are independent of 3–5. Main stays deployable
after every PR. No feature flags needed until Task 5 flips the deployment model.
