# Hosted Deployment Runbook

This is the operational runbook for the shared, multi-tenant soundboard at
`dashboard.soundbored.app`. Deployment is **Coolify-first**: Coolify supplies the
reverse proxy, certificates, and persistent storage. There is no Caddy in this
stack; the container shape (image, volumes, environment) below is what Coolify
consumes.

## Architecture in one paragraph

One shared bot instance serves every guild. Tenants are rows in the `guilds`
table; a signed-in user scopes to a tenant through their session (`guild_id`),
and a shareable `/g/{slug}` path resolves the tenant by slug. Tenancy needs no
env vars: with both gating envs unset, the deployment is open-signup and
tenant-row-driven. Billing (Stripe) is dormant unless `STRIPE_SECRET_KEY` is
set; see the main README for those keys.

## DNS records

| Record | Type | Value | Purpose |
|---|---|---|---|
| `dashboard.soundbored.app` | A/AAAA | VPS address | The app itself (required) |
| `soundbored.app` | A/AAAA | VPS address | Marketing site / apex (operator) |
| `*.soundbored.app` | A/AAAA | VPS address | Only if/when subdomain routing is enabled (deferred) |

v1 uses path-based tenants (`/g/{slug}`), so the wildcard record is **not**
required. The subdomain flip is a later upgrade: point the wildcard record,
configure the wildcard domain in Coolify (with its certificate strategy), and
set `TENANT_BASE_HOST=soundbored.app` (already set in the compose). The plug
(`SoundboardWeb.Plugs.Tenant`) already resolves subdomains; no code changes.

## Deploying with Coolify (primary path)

1. Create a new resource from a Docker Compose file with one `app` service
   running `christom/soundbored:<tag>`; mount the two named volumes and pass
   the environment from `.env` as described below.
2. Attach persistent storage for both named volumes (`app_uploads`,
   `app_db`) to Coolify's persistent storage so upgrades and restarts keep
   sounds and the database.
3. Set the environment from `.env` (Coolify's env editor or a linked env
   file). Required: `DISCORD_TOKEN`, `DISCORD_CLIENT_ID`,
   `DISCORD_CLIENT_SECRET`, `SECRET_KEY_BASE`
   (`mix phx.gen.secret` or `openssl rand -base64 48`).
   Set `PHX_HOST=dashboard.soundbored.app`, `SCHEME=https`,
   `TENANT_BASE_HOST=soundbored.app`, and optionally
   There is no free tier on hosted: every tenant needs an active Stripe subscription before it can be provisioned (the webhook is the only provisioning path). There is also no default storage cap anywhere: self-hosted installs are uncapped (unlimited), and hosted caps exist only because a subscription wrote them.
   **Leave `DISCORD_REQUIRED_GUILD_ID` and `DISCORD_REQUIRED_ROLE_IDS`
   unset** — hosted mode is open signup, and `RoleChecker` treats unset as
   open. Do not set them "for safety": they would lock signups to one guild's
   members and break the hosted funnel.
4. In Coolify's domain settings, add `https://dashboard.soundbored.app` and let
   Coolify provision the certificate (Let's Encrypt HTTP challenge). Coolify
   proxies the container's port 4000.
5. Deploy. The container entrypoint runs `mix ecto.migrate` on boot, so the
   first deploy creates and migrates the schema. Existing single-tenant
   deployments upgrade through the same path: migrations run on boot and the
   backfill repoints legacy rows, verified by the upgrade rehearsal kept on
   the feature branch (not shipped on main).

## Why each env is set or unset

| Env | In hosted mode | Why |
|---|---|---|
| `DISCORD_TOKEN`, `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET` | set | The shared bot's identity; sign-in and guild enumeration depend on them. |
| `SECRET_KEY_BASE` | set | Session signing; rotating it signs everyone out. |
| `PHX_HOST` / `SCHEME` | `dashboard.soundbored.app` / `https` | URL generation and OAuth redirect correctness behind the proxy. |
| `TENANT_BASE_HOST` | `soundbored.app` | Enables the subdomain resolution path; harmless while no wildcard DNS exists. Remove it only to hard-disable subdomains. |
| — | — | There is no default storage cap. Self-hosted is unlimited; hosted caps come only from subscriptions (the webhook writes the plan's exact cap). |
| `DISCORD_REQUIRED_GUILD_ID`, `DISCORD_REQUIRED_ROLE_IDS` | **unset** | Open signups. Setting them would gate sign-in to one guild's roles and break hosted onboarding. |
| `AUTO_JOIN` | operator choice | Voice join behavior is a product preference, not a tenancy setting. |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, price ids | unset until SB-3 launches | Billing dormant without them: no billing routes, no payment behavior. |

## Operator cutovers

The operator owns DNS and the cutover window; the deployer never touches DNS.

1. **First deploy.** Add the `app` DNS record, then deploy via Coolify.
   Verify: `https://dashboard.soundbored.app` serves the app behind a valid
   certificate.
2. **Sign-in check.** Sign in with a Discord account, invite the bot to a
   guild, and confirm the guild appears at `/guilds`.
3. **Subdomain flip (deferred).** Only when wanted: add the wildcard DNS
   record, configure the wildcard domain in Coolify, confirm
   `TENANT_BASE_HOST` is set, and test a provisioned guild's subdomain.

## Volume backups

- `app_db` holds the SQLite database (`soundboard_prod.db` plus `-wal`/
  `-shm` sidecars). Back up all three files together; SQLite is only
  consistent when the WAL is captured atomically. Prefer Coolify's scheduled
  volume backup, or `sqlite3 /data/db/soundboard_prod.db ".backup ..."`
  inside the container for a hot consistent copy.
- `app_uploads` holds user-uploaded sounds. Snapshot it on the same schedule;
  a database restore without its sounds leaves dangling rows.

## Per-guild cap overrides

There is no free tier and no default cap. A tenant row is created only by the Stripe webhook after checkout, so every hosted soundboard is a paying one with its plan's exact cap. Self-hosted installs are uncapped — storage is limited only by disk. Paid tiers and
one-off overrides are per-row: `UPDATE guilds SET max_storage_bytes = <bytes>
WHERE discord_guild_id = '<id>';`. Billing (SB-3) writes this column from
webhook events; manual overrides are the operator's lever for comped guilds.

## Cancelled subscriptions and the retention window

When a Stripe subscription is deleted, the webhook zeroes the guild's
`max_storage_bytes`. The guild becomes inert: uploads and playback are
refused, but the row and its sounds remain so an accidental cancellation is
recoverable by resubscribing. The retention policy: **30 days** after
cancellation, the operator may purge the row and its files (a purge is a
manual step, never automatic). Do not purge earlier; the user may be fixing a
payment method.


## Operational watch items

- **SQLite is a single writer, running in WAL mode** (prod config sets
  `journal_mode: :wal` and `busy_timeout: 5000`): concurrent reads never block,
  writes queue instead of erroring. At launch volume this is comfortable;
  sustained write contention (log shows busy timeouts exhausting) is the signal
  to move to Postgres.
- **Wildcard certificates.** Before enabling the subdomain flip, make sure the
  certificate strategy for `*.soundbored.app` does not issue certs for any
  hostname (on-demand issuance with an ask endpoint that verifies the slug
  exists), or use a DNS-challenge wildcard cert.
- **Role gating is off in hosted mode.** The paywall (SB-3) guards tenant
  creation, not sign-in. Anyone with a Discord account can sign in; only paid
  guilds get a row with capacity.
