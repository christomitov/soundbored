# Security Fixes — v1.8.0

**Status:** Complete
**Branch:** `fix/security-db-exposure-tokens-traversal`

**Vulnerabilities addressed:**

1. SQLite DB inside `priv/static/uploads/` — served by `UploadController`
2. Plaintext API tokens in `api_tokens.token` column
3. `params["filename"]` flowed unsanitized into `File.rename` via `UploadsPath.file_path/1` (path traversal)
4. User display names were used as filesystem paths — fixed by introducing `storage_key` (UUID) separate from `filename` (display only)
5. Upload file size limit — added configurable 10 MB cap
6. Upload content validation — added magic bytes check to reject non-audio files

---

## Phase 1 — Move database out of uploads directory ✓

- `config/config.exs`, `config/dev.exs` → `database: "priv/db/soundboard_dev.db"`
- `config/test.exs` → `priv/db/soundboard_test.db` (was at project root, ungitignored)
- `config/prod.exs` → `database: "/app/priv/db/soundboard_prod.db"`
- `config/runtime.exs` → hardcoded `/app/priv/db/soundboard_prod.db`
- `docker-compose.yml` → added `soundbored_db:/app/priv/db` named volume
- `Dockerfile` → `VOLUME ["/app/priv/static/uploads", "/app/priv/db"]`
- `entrypoint.sh` → migrates DB from old uploads path directly to `priv/db`; `mkdir -p` runs unconditionally
- `.gitignore` → single `/priv/db/` pattern covers dev, test, and WAL files
- `lib/soundboard_web/controllers/upload_controller.ex` → extension allowlist (defense-in-depth): only `.mp3 .wav .ogg .m4a .flac` served; all other requests → 404

## Phase 2 — Remove plaintext API token storage ✓

- Migration `20260510000001_remove_token_plain_from_api_tokens.exs` drops `api_tokens.token` column
- `lib/soundboard/accounts/api_token.ex` → removed `field :token, :string`
- `lib/soundboard/accounts/api_tokens.ex` → removed `token: raw` from changeset attrs
- `lib/soundboard_web/live/settings_live.ex` → example curl only shows `:new_token` assign (set at creation, cleared on reload); masked placeholder shown for existing tokens

## Phase 3 — UUID storage keys ✓

- Migration `20260510000002_add_storage_key_to_sounds.exs` adds `storage_key` column; existing rows get the old filename as storage key (files already on disk under that name, no rename needed)
- `lib/soundboard/sounds/sound.ex` → added `field :storage_key, :string`
- `lib/soundboard/sounds/uploads/source.ex` → generates `Ecto.UUID.generate() <> ext` as `storage_key`; uses `UploadsPath.file_path(storage_key)` for disk writes
- `lib/soundboard/sounds/uploads/creator.ex` → passes `storage_key:` to `Sound.changeset/2`
- `lib/soundboard/sounds/management.ex` → `update_sound` no longer renames files (storage_key is immutable); `delete_sound` uses `sound.storage_key`
- `lib/soundboard/audio_player/sound_library.ex` → `resolve_upload_path/1` uses `sound.storage_key`
- LiveView templates (`soundboard_live.html.heex`, `favorites_live.html.heex`, `edit_modal.ex`) → all `/uploads/` URL constructions now use `sound.storage_key`

## Phase 4 — Upload size limit and magic bytes ✓

- `config/config.exs` → `max_upload_bytes: 10_000_000` default
- `config/runtime.exs` → `MAX_UPLOAD_BYTES` env var override in prod
- `lib/soundboard_web/endpoint.ex` → `Plug.Parsers length:` reads `Application.compile_env(:soundboard, :max_upload_bytes, 10_000_000)`
- `lib/soundboard_web/live/soundboard_live.ex` → `allow_upload max_file_size:` reads runtime config; error message shows computed MB value
- `mix.exs` → added `{:magic_bytes, "~> 0.2"}`
- `lib/soundboard/sounds/uploads/source.ex` → `validate_magic_bytes/1` called in `:create` mode; rejects anything not in `audio/mpeg audio/wav audio/ogg audio/mp4 audio/flac audio/aiff`
