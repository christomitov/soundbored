# Security Fixes Plan

**Status:** In Progress
**Branch:** `fix/security-db-exposure-tokens-traversal`

**Findings addressed:**
1. SQLite DB inside `priv/static/uploads/` — served by `UploadController`, any authenticated user can download it
2. Plaintext API tokens stored in `api_tokens.token` column, rendered on every settings page load
3. `params["filename"]` flows unsanitized into `File.rename` via `UploadsPath.file_path/1` (path traversal)
4. Root cause of 3: user display names are filesystem paths — fix by introducing `storage_key` (UUID) separate from `filename` (display only)

---

## Phase 1 — Move database out of uploads directory

**`config/config.exs:77`**
```elixir
database: "priv/static/uploads/database.db"
→ database: "priv/soundboard_dev.db"
```

**`config/prod.exs:12`**
```elixir
database: "/app/priv/static/uploads/soundboard_prod.db"
→ database: "/app/data/soundboard_prod.db"
```

**`config/runtime.exs:120`**
```elixir
database_path = Path.join(:code.priv_dir(:soundboard), "static/uploads/soundboard_prod.db")
→ database_path = "/app/data/soundboard_prod.db"
```

**`docker-compose.yml`** — add second named volume:
```yaml
volumes:
  - soundbored_data:/app/priv/static/uploads   # unchanged
  - soundbored_db:/app/data                    # new

volumes:
  soundbored_data:
  soundbored_db:
```

**`Dockerfile`**
```dockerfile
VOLUME ["/app/priv/static/uploads"]
→ VOLUME ["/app/priv/static/uploads", "/app/data"]
```

**`entrypoint.sh`** — migrate existing installs (before `mix ecto.migrate`):
```sh
OLD_DB="/app/priv/static/uploads/soundboard_prod.db"
NEW_DB="/app/data/soundboard_prod.db"
if [ -f "$OLD_DB" ] && [ ! -f "$NEW_DB" ]; then
  echo "Migrating database from old location..."
  cp "$OLD_DB" "$NEW_DB"
fi
```

**`lib/soundboard_web/controllers/upload_controller.ex`** — defense-in-depth extension allowlist:
```elixir
@allowed_extensions ~w(.mp3 .wav .ogg .m4a .flac)

def show(conn, %{"path" => path}) do
  with {:ok, file_path} <- UploadsPath.safe_joined_path(path),
       true <- File.regular?(file_path),
       true <- Path.extname(file_path) |> String.downcase() in @allowed_extensions do
    send_file(conn, 200, file_path)
  else
    _ -> send_resp(conn, 404, "Not found")
  end
end
```

---

## Phase 2 — Remove plaintext API token storage

> **⚠ Implication for existing users:** The `token` column is dropped permanently.
> Existing tokens continue to work (auth uses the hash). However, the token value can no
> longer be displayed — users who never copied their token must revoke and regenerate.
> Add a notice to the settings page.

**New migration** `TIMESTAMP_remove_token_plain_from_api_tokens.exs`:
```elixir
def up, do: alter table(:api_tokens), do: remove :token
def down, do: alter table(:api_tokens), do: add :token, :string, null: false, default: ""
```

**`lib/soundboard/accounts/api_token.ex`** — remove `field :token, :string`, update `@type t` and `@moduledoc`

**`lib/soundboard/accounts/api_tokens.ex`** — remove `token: raw` from changeset attrs in `generate_token/2`

**`lib/soundboard_web/live/settings_live.ex`**
- `load_tokens/1`: remove `example` fallback that reads `token.token` from DB; example curl only populates from `:new_token` socket assign (set immediately after creation, cleared on reload)
- Template: replace `token.token` / `data-copy-text={token.token}` with masked display or `"<your-token>"` placeholder
- Add notice: "API token values are shown once at creation and cannot be retrieved afterwards."

---

## Phase 3 — GUID-based storage keys

**Goal:** User-supplied display names never become filesystem paths. Existing files renamed in migration.

**New migration** `TIMESTAMP_add_storage_key_to_sounds.exs`:
```elixir
def up do
  alter table(:sounds) do
    add :storage_key, :string, null: false, default: ""
  end
  flush()

  {:ok, rows} = Soundboard.Repo.query("SELECT id, filename FROM sounds")
  uploads_dir = Soundboard.UploadsPath.dir()

  Enum.each(rows.rows, fn [id, filename] ->
    ext = Path.extname(filename)
    storage_key = Ecto.UUID.generate() <> ext
    old_path = Path.join(uploads_dir, filename)
    new_path = Path.join(uploads_dir, storage_key)
    if File.exists?(old_path), do: File.rename!(old_path, new_path)
    Soundboard.Repo.query!("UPDATE sounds SET storage_key = ? WHERE id = ?", [storage_key, id])
  end)

  create unique_index(:sounds, [:storage_key])
end

def down do
  {:ok, rows} = Soundboard.Repo.query("SELECT filename, storage_key FROM sounds")
  uploads_dir = Soundboard.UploadsPath.dir()
  Enum.each(rows.rows, fn [filename, storage_key] ->
    old_path = Path.join(uploads_dir, storage_key)
    new_path = Path.join(uploads_dir, filename)
    if File.exists?(old_path), do: File.rename!(old_path, new_path)
  end)
  drop_if_exists index(:sounds, [:storage_key])
  alter table(:sounds), do: remove :storage_key
end
```

**`lib/soundboard/sounds/sound.ex`** — add `field :storage_key, :string`; add to `cast` and `validate_required`

**`lib/soundboard/sounds/uploads/source.ex`**
- Add `storage_key` to the `%Source{}` struct
- Generate `storage_key = Ecto.UUID.generate() <> ext` in `prepare/2`
- Use `UploadsPath.file_path(source.storage_key)` for `dest_path`
- `validate_destination_filename` checks DB uniqueness on `filename` only (display name)

**`lib/soundboard/sounds/uploads/creator.ex`** — pass `storage_key: source.storage_key` to `Sound.changeset/2`

**`lib/soundboard/sounds/management.ex`**
- `update_sound`: remove `maybe_rename_local_file` — storage_key is immutable, only `filename` (display) changes in DB
- `delete_sound` / `maybe_remove_local_file`: use `UploadsPath.file_path(sound.storage_key)`

**`lib/soundboard/audio_player/sound_library.ex`** — `resolve_upload_path/1`: use `sound.storage_key`

**LiveView templates** — find all `/uploads/{filename}` URL constructions:
```sh
rg "uploads.*filename|filename.*uploads" lib/soundboard_web/ --include="*.ex" --include="*.heex"
```
Replace with `sound.storage_key`.

---

## Verification

```sh
mix format && mix credo --strict && mix test
# manual: upload a sound → plays correctly
# manual: GET /uploads/soundboard_prod.db → 404
# manual: GET /uploads/anyfile.db → 404
# manual: create API token → value shown once; refresh → masked/placeholder shown
# manual: rename a sound → file stays under UUID name, display name updates
# manual: rename with "../evil" in name → error returned, no file moved
```
