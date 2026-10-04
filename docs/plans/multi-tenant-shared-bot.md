# Multi-Tenant Shared Bot Implementation Plan

**Status:** Implemented on `feature/multi-tenant` (Tasks 1–4 with deviations noted below). Task 5 (routing + deploy as multi-tenant host) is not done. Wildcard-host config (`TENANT_BASE_HOST`) and subdomain tenant resolution are in place; Caddy/DNS is out of scope.

## Production upgrade path (verified by migration test)

`mix ecto.migrate` on an existing deployment is additive and data-preserving:
`guilds` table created; `sounds.guild_id`/`byte_size` and
`user_sound_settings.guild_id` added and backfilled; unique filename index
swapped to per-guild `(guild_id, filename)`; the join/leave flags get
per-guild unique indexes. Backfill writes the default guild, and `byte_size`
defaults to `0` so caps never block retroactively. Rollback (`down`) is
data-preserving. See `test/soundboard/migrations/data_migrations_test.exs`.

## Quality gate

Full VibeKit suite adopted (`mix ci` = compile --warnings-as-errors, format
check, test, credo --strict, dialyzer, ex_dna --max-clones 0, reach.check).
The gate also introduced `Soundboard.Boundary`: every bare `rescue` in the
audio, Discord, and tenant modules became `rescue in @boundary_exceptions`, so
each rescue names the exceptions it catches instead of catching every raise.
This is a lint-driven rewrite of existing rescue sites, not new error handling.

## Verified design decisions

- **EDA voice is already per-guild** (`EDA.Voice.Registry` + `DynamicSupervisor`, sessions keyed `{:session, guild_id}`) — simultaneous multi-guild voice works below our code. Only `Soundboard.AudioPlayer` needed the per-guild refactor.
- **Backward compatibility mechanism:** every guild-scoped function takes optional `guild_id` defaulting to `Tenants.default_guild_id()`. Resolution order is `SOUNDBOARD_DEFAULT_GUILD_ID` → `DISCORD_REQUIRED_GUILD_ID` → **sole-bot-guild discovery** (`GuildCache`, for zero-config single-guild deployments that set neither env) → `"default"`. `Tenants.reconcile_default_guild/0` repoints backfilled `"default"` rows to the real bot guild after upgrade. Zero-config single-guild deployments behave identically.
- **Storage stays flat** (UUID storage keys) — guild scoping in DB only; no file moves. No per-guild uploads path.
- **Storage caps:** `sounds.byte_size` recorded at upload; guild usage = `SUM(byte_size)`; cap per `guilds.max_storage_bytes`, default from `SOUNDBOARD_DEFAULT_STORAGE_BYTES` (fallback 2GB). Over-cap uploads are rejected before insert by the upload creator
(`Sounds.Uploads.Creator`). Existing rows backfilled `byte_size = 0` so nobody
gets blocked retroactively. Per-guild cap override = the paid-tier knob.
- **Defaults chosen:** free cap 2GB; role gating stays global env for v1; single branch. Stats are now **per-guild** (see deviations).
- Playback PubSub topic per guild; LiveViews subscribe to their tenant's topic.
- Tenant resolution plug (`SoundboardWeb.Plugs.Tenant`): subdomain slug → session `guild_id` → default guild; unknown subdomain 404s. Provisioning/switch UI lives in this app (`GuildController` at `/guilds`); onboarding-portal polish/billing/analytics lives in `soundbored-app`.
**Related:** `../soundbored-app/` (marketing site + future onboarding portal)

**Goal:** Turn Soundbored from one-deployment-per-Discord-server into a single
multi-tenant deployment: ONE hosted bot instance serves many guilds, sounds are
scoped per guild, and users onboard by inviting the shared bot — no per-user bot
tokens, no per-user Docker containers.

**Why:** Discord has no API to create bots on a user's behalf, and one bot token
cannot run in multiple processes. Hosting one shared bot that users invite into
their servers is the only true one-click onboarding, and it collapses the infra
model to a single deployment.

**Constraint:** Every PR leaves `main` shippable as the existing single-guild
deployment. Multi-guild behavior is enabled incrementally.

---

## Current-state gaps (verified in code)

| Gap | Location |
|---|---|
| `AudioPlayer` was a singleton GenServer holding a single `voice_channel: {guild_id, channel_id}` — one voice connection app-wide | `lib/soundboard/audio_player.ex` (now Registry + DynamicSupervisor) |
| `Sound` schema had no `guild_id`; library was global per deployment | `lib/soundboard/sound.ex` (now has `guild_id`, `byte_size`) |
| Web layer (LiveViews, uploads, auth) assumed one tenant | `lib/soundboard_web/` |

What already worked for multi-guild: `Discord.Handler`/`Consumer` are
event-driven and guild-keyed; `GuildCache` is keyed per guild;
`DISCORD_REQUIRED_GUILD_ID` is optional.

---

## Tasks

### Task 1: Guild-scoped data model ✅
- `guild_id` (string, snowflake) on `sounds` and `user_sound_settings`; `byte_size` on `sounds`.
- Globally-unique filename index replaced with composite `(guild_id, filename)`; per-guild unique indexes for join/leave sounds.
- Backfill migration: existing rows get the default guild (`default_guild_id/0`).
- `Sounds` context scoped by guild_id. **Storage path stays flat** — no per-guild uploads directory (see "verified design decisions").

### Task 2: Per-guild audio playback ✅
- `Soundboard.AudioPlayer` now routes through `Registry` + `DynamicSupervisor` (`Soundboard.AudioPlayer.Supervisor`), one player process per guild (`audio_player/server.ex`), started on demand.
- Public API is guild-explicit (`play/…`, `set_voice_channel/…`, `stop_sound/…`); all call sites updated (`Discord.Handler`, LiveViews, API).
- Per-guild queue/watchdog/rejoin behavior ported into `audio_player/{playback_queue,playback_engine,voice_session,notifier,sound_library}.ex`.
- Single-guild deployments behave identically to today.

### Task 3: Multi-guild web tenancy ✅ (with deviations)
- **Deviation: no OAuth `guilds` scope and no `Manage Server` permission check.** The guild switcher enumerates the **shared bot's** guilds via `Tenants.bot_guilds/0` (`GuildCache`), not the signed-in user's authorized guilds.
- Tenant resolution (`SoundboardWeb.Plugs.Tenant`): subdomain slug → session `guild_id` → default guild; unknown subdomain 404s.
- Session stores active `guild_id`; `SoundboardLive`, `FavoritesLive`, `StatsLive` scope to it.
- **Role gating stays a global env pair** (`RoleChecker`) for v1 — per-guild role config deferred, not implemented.

### Task 4: Tenants table + provisioning ✅
- `guilds` table (`id, discord_guild_id, slug, name, max_storage_bytes, timestamps`); unique indexes on `discord_guild_id` and `slug`.
- `Tenants` context: `get_or_create_guild/2`, `bot_guilds/0`, storage cap helpers (`storage_used`, `storage_cap`, `storage_remaining`, `within_storage_limit?`).
- Provisioning = `GuildController.switch/2` calls `get_or_create_guild`, auto-creating a **provisional slug `guild-<id>`** on first use.
- **`Tenants.claim_slug/2` and `slug_available?/1` are implemented and tested but not wired to any route/UI yet** — the "claim a subdomain" step is not reachable from the app.
- `DISCORD_REQUIRED_GUILD_ID`/`ROLE_IDS` still drive gating via env; runtime gating does not yet read the `guilds` table.

### Task 5: Routing + deploy as multi-tenant host ☐ (not started)
- Wildcard subdomain resolution is implemented in the `Tenant` plug (driven by `TENANT_BASE_HOST`), but there is **no `/s/{slug}` path fallback** and no deployment/DNS/Caddy setup.
- Single-container deploy config, on-demand TLS, and `*.soundbored.app` DNS are all out of scope for this repo.

---

## Out of scope for ../soundboard/ (tracked in soundbored-app)

- Onboarding portal / dashboard UI polish (incl. slug-claim UI), Stripe billing, analytics.
- DNS/Caddy/VPS setup — infra, not code.

## Ship order

Tasks 1–4 land on `feature/multi-tenant`; Task 5 is independent. Main stays
deployable after every PR. No feature flags needed until Task 5 flips the
deployment model.
