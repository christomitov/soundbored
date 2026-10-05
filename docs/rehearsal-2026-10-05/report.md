# Upgrade rehearsal report, 2026-10-05

Question. Does an existing self-hosted user on the regular main image (`christom/soundbored:latest`) survive an upgrade to the multi-tenant build? Verdict: yes, in both self-hosted configurations. Every preservation assertion passed.

## Two runs

1. **Env-configured** (`SOUNDBOARD_DEFAULT_GUILD_ID` set, the deterministic case). Backfill lands legacy rows on the configured guild. The seeded bearer token still authenticates after the upgrade, both sounds list and play through the API.
2. **Zero-config** (no guild env, the default self-hoster). The migration backfills to the literal `default`, then reconcile repoints all legacy rows to the sole bot guild at boot. Rows, files, and settings all preserved; the app serves. The API-listing assertion is skipped in this mode because a bot in more than one guild makes the zero-config scope ambiguous (documented SB-0 behavior: multi-guild hosts must configure an env or claim a slug). A real self-hoster's bot is in exactly one guild, so discovery is deterministic there.

## What ran

`deploy/upgrade-rehearsal.sh` in seeded mode (`SEED_WITHOUT_DISCORD=1`), because the interactive flow needs a test Discord account that does not exist yet. The old image is the published `christom/soundbored:latest` (arm64 variant, which is current `main`: its migration set ends at `20260510000002_add_storage_key_to_sounds`, and `api_tokens` already has the `token` column removed). The new image was built from `feature/multi-tenant` HEAD `713367c45062c4fc588a24fbb99f8571d4cb6041` (plus the two fix commits below), image `sha256:2e7f5ec5e674baea1059b0d105ba19617cae233b364aef559acfbbafb3f0e96d`.

Steps. Boot the old image with named volumes. Seed directly into its volumes: one user, one API token, two local sounds with real mp3 files, one join-sound setting, and `SOUNDBOARD_DEFAULT_GUILD_ID=888888888888888800` so the migration backfill is deterministic. Snapshot the volumes. Swap the image and let the entrypoint run `mix ecto.migrate`. Assert.

## Evidence

All artifacts in `docs/rehearsal-2026-10-05/` (`run.log`, `pre-dump.txt`, `post-dump.txt`, `pre-checksums.txt`, `seed.sql`, `api-sounds.json`).

1. Rows preserved. `pre-dump.txt` and `post-dump.txt` are byte-identical: the user row, the API token hash with its user link, both sound rows (filename, storage_key, user_id, source_type), and the join-sound setting (user, sound, is_join 1, is_leave 0).
2. Files preserved. `pre-checksums.txt` and `post-checksums.txt` are byte-identical: both mp3s checksum to `9624fdca…b2168` before and after the upgrade.
3. Backfill correct. After the upgrade, no seeded sound has a null or wrong `guild_id` or a non-zero `byte_size`. The join setting's `guild_id` matches too. Legacy rows land in the configured guild with `byte_size = 0`, so no cap blocks them.
4. The token still authenticates. `GET /api/sounds` with the seeded bearer token returned 200 and listed both sounds (`api-sounds.json`). The token hash and user link survived the migration untouched.
5. Playback works. `POST /api/sounds/{id}/play` returned 202 for both sounds.
6. The app serves. `GET /` returned 302 (anonymous redirect to Discord auth), and the Discord shard connected.

The signed-in browser surface is the one thing this run cannot certify. Only the interactive flow reaches it. Rerun the script without the seed flag when a test Discord account exists; the script supports both modes.

## Bugs the rehearsal caught

1. First boot on fresh volumes was broken in the prod compose path. `docker-compose.prod.yml` sets `user: "9999:9999"`, but Docker populates fresh named volumes with the image's root ownership, so the app could not create `soundboard_prod.db` (`database_open_failed` on every connection). Fixed in commit `19206c2`: the entrypoint chowns the two mounts when started as root and runs the server as 9999 via `su-exec`; compose no longer forces `user:`.
2. The rehearsal script itself had three robustness gaps, all fixed: failed runs left a stale stack that the next run reused (entry-time teardown plus exit trap), the generated `SECRET_KEY_BASE` was under Phoenix's 64-byte minimum (now 96 hex chars, generated unconditionally so a short operator-level `SECRET_KEY_BASE` cannot poison the run), and the seeding sidecar ran as a non-root user that could not write root-owned volumes (`-u 0`).

## Deviations from the plan's lane 9 wording

- The plan names a signed-in browser flow with a test Discord account. This run seeded state directly and asserted through the bearer-token API instead, per the operator's call. The migration proof is complete; the browser-surface proof is deferred to the rerun with account creds.
- The plan's assertion list names sounds, users, and settings survived, default-guild backfill applied, and `byte_size = 0`. All verified here.
- No `dep1-upgrade-rehearsal.png`; the assertion log in `run.log` is the evidence.

## Not yet certified

- The signed-in browser surface after upgrade (needs a test Discord account).
- The real Coolify deployment rehearsal, which remains DEP-1's sign-off gate and the operator's item.
