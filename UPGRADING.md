# Upgrading Soundbored

## Unreleased (multi-tenant)

This release turns Soundbored into a multi-tenant deployment: one shared bot serves many guilds, and sounds are scoped per guild. The upgrade is automatic and data-preserving. Single-guild deployments that set none of the new variables behave exactly as before.

### Database migration

`mix ecto.migrate` (run automatically by the container entrypoint) creates the `guilds` table, adds `guild_id` and `byte_size` to `sounds` and `guild_id` to `user_sound_settings`, and backfills every existing row with the default guild. Existing sound files stay where they are; there is no per-guild uploads directory. `byte_size` is backfilled as `0`, so no existing deployment can hit the new storage cap retroactively. The migration is additive and `down` is also data-preserving.

### Storage cap behavior change

Uploads are now checked against the guild's storage cap (sum of sound `byte_size` vs `max_storage_bytes`) before the sound is inserted. Over-cap uploads are rejected with an error asking the user to remove sounds or upgrade. Per-guild cap overrides (`guilds.max_storage_bytes`) are the knob for paid tiers.

### New environment variables (all optional)

| Variable | Purpose |
| --- | --- |
| `SOUNDBOARD_DEFAULT_GUILD_ID` | Guild id used to scope sounds when no tenant is specified. Falls back to `DISCORD_REQUIRED_GUILD_ID`, then the bot's sole guild, then the literal `default`. |
| `SOUNDBOARD_DEFAULT_STORAGE_BYTES` | Default per-guild storage cap in bytes. Defaults to `2147483648` (2GB). |
| `TENANT_BASE_HOST` | Base host for tenant subdomains, e.g. `soundbored.app` resolves `{slug}.soundbored.app` to that guild's soundboard. Empty disables subdomain routing. |

## v1.8.0 (security release)

This release contains three breaking infrastructure changes. **Read all three sections before upgrading.**

---

### 1. New Docker volume required — database moved out of uploads directory

The SQLite database has been moved from the uploads directory (`/app/priv/static/uploads/`) to a dedicated directory (`/app/priv/db/`). This prevents the database file from being served as a static asset.

**docker-compose.yml change required:**

```yaml
volumes:
  - soundbored_data:/app/priv/static/uploads
  - soundbored_db:/app/priv/db     # ← add this

volumes:
  soundbored_data:
  soundbored_db:                   # ← add this
```

The container's entrypoint will automatically copy your existing database to the new location on first boot if it finds the old file and the new path is empty. No manual data migration is needed for standard Docker Compose deployments.

**Custom deployments:** If you mount the uploads directory by path rather than named volume, ensure `/app/priv/db` is also a persistent mount before starting the upgraded container.

---

### 2. API token plaintext column removed

The `api_tokens.token` column (which stored token values in plaintext alongside the hash) has been dropped. The Ecto migration runs automatically on startup via `entrypoint.sh`.

**Impact:** No action required for normal use. If you have external scripts or tooling that reads `api_tokens.token` directly from the database, update them — the column no longer exists. Token hashes remain in the `token_hash` column.

---

### 3. Sound files renamed on disk — storage keys are now UUIDs

Sound files on disk have been renamed from their display name (e.g. `wow.mp3`) to a UUID-based storage key (e.g. `a3f2c1d0-….mp3`). This decouples the user-visible filename from the filesystem path, eliminating a path-traversal vector in the rename flow.

The Ecto migration (`20260510000002_add_storage_key_to_sounds.exs`) handles the rename automatically for all existing sounds when the container starts.

**Impact:**
- Direct filesystem access: files in the uploads directory will have new UUID names after the migration.
- The `/uploads/<key>` URLs served by the application update automatically — no broken links in the UI.
- Backups taken of the uploads directory before upgrading will still work; the migration only renames files in-place and does not delete originals on failure.
