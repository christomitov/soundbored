#!/usr/bin/env bash
#
# Upgrade rehearsal: proves an existing single-tenant deployment upgrades to
# the multi-tenant image with sounds, users, and join/leave settings intact.
#
# It is the standing guard for the hosted upgrade path: run it whenever a
# migration changes. The real Coolify deployment is the upgrade surface this
# script certifies; the local compose stack below is the development harness
# for iterating on the script itself.
#
# Requires: docker, node (with npx playwright), and these env vars:
#   DISCORD_CLIENT_ID, DISCORD_TOKEN      shared bot credentials (from .env)
#   TEST_DISCORD_EMAIL, TEST_DISCORD_PASSWORD
#                                         a real Discord test account that
#                                         can sign in and consent to the bot
#   OLD_IMAGE (optional, default christom/soundbored:latest)
#   NEW_IMAGE (optional, default christom/soundbored:multi-tenant)
#
# Seeded mode: SEED_WITHOUT_DISCORD=1 skips the Discord sign-in. It seeds a
# user, an API token, two local sounds, and a join-sound setting directly into
# the database and uploads volume, then asserts on the same data after the
# upgrade through file checksums, table dumps, and the bearer-token API. That
# certifies the migration; the signed-in browser surface is only reached by
# the interactive flow.
#
# Usage: deploy/upgrade-rehearsal.sh
set -euo pipefail

OLD_IMAGE="${OLD_IMAGE:-christom/soundbored:latest}"
NEW_IMAGE="${NEW_IMAGE:-christom/soundbored:multi-tenant}"
SEEDED="${SEED_WITHOUT_DISCORD:-0}"
REHEARSAL_GUILD_ID="888888888888888800"
DISCORD_ID="888888888888888801"
RAW_TOKEN="sb_rehearsal0000000000000000000000000000000000000000000000"
SEED_DATE="2026-01-01 00:00:00"
PROJECT="soundbored-rehearsal"
PORT="${REHEARSAL_PORT:-4100}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/soundbored-rehearsal.XXXXXX")"
COMPOSE_FILE="$WORKDIR/docker-compose.yml"
BASE_URL="http://127.0.0.1:$PORT"

log() { printf '\n=== %s ===\n' "$1"; }
fail() { printf 'REHEARSAL FAILED: %s\n' "$1" >&2; exit 1; }

if [ "$SEEDED" = 1 ]; then
  for var in DISCORD_CLIENT_ID DISCORD_TOKEN; do
    [ -n "${!var:-}" ] || fail "$var must be set (see header)"
  done
else
  for var in DISCORD_CLIENT_ID DISCORD_TOKEN TEST_DISCORD_EMAIL TEST_DISCORD_PASSWORD; do
    [ -n "${!var:-}" ] || fail "$var must be set (see header)"
  done
fi
command -v docker >/dev/null || fail "docker not found"
if [ "$SEEDED" != 1 ]; then
  node --version >/dev/null 2>&1 || fail "node not found (needed for Playwright)"
fi

sha256() {
  if command -v sha256sum >/dev/null; then
    printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else
    printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
  fi
}

new_uuid() {
  if command -v uuidgen >/dev/null; then
    uuidgen | tr 'A-Z' 'a-z'
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

app_ctr() { docker compose -p "$PROJECT" ps -qa app | head -1; }

# SQL against the rehearsal database from a sidecar sharing the app volumes.
db() {
  docker run --rm -u 0 --volumes-from "$(app_ctr)" keinos/sqlite3 \
    sqlite3 /app/priv/db/soundboard_prod.db "$1"
}

# The rows the upgrade must preserve, in a canonical format so the pre and
# post dumps can be diffed byte for byte.
dump_state() {
  db "SELECT 'user', discord_id, username FROM users WHERE discord_id = '$DISCORD_ID';
      SELECT 'token', token_hash, user_id FROM api_tokens WHERE token_hash = '$TOKEN_HASH';
      SELECT 'sound', filename, storage_key, user_id, source_type FROM sounds WHERE filename LIKE 'rehearsal-%';
      SELECT 'setting', user_id, sound_id, is_join_sound, is_leave_sound FROM user_sound_settings
        WHERE sound_id IN (SELECT id FROM sounds WHERE filename LIKE 'rehearsal-%');" | sort
}

checksum_files() {
  docker run --rm --volumes-from "$(app_ctr)" alpine \
    sha256sum "/app/priv/static/uploads/$KEY1" "/app/priv/static/uploads/$KEY2"
}

log "Staging rehearsal stack in $WORKDIR"
cd "$(dirname "$0")/.."

# A failed earlier run leaves the project behind, and compose does not hash
# env_file contents, so it would happily reuse a stale container.
trap 'docker compose -p "$PROJECT" down >/dev/null 2>&1 || true' EXIT
trap 'fail "interrupted"' INT TERM
docker compose -p "$PROJECT" down -v >/dev/null 2>&1 || true

# Rehearsal compose: the prod image shape (same volumes, entrypoint, user) on a
# local port, without the Coolify proxy. SCHEME is http locally.
cat >"$COMPOSE_FILE" <<EOF
services:
  app:
    image: \${SOUNDBORED_IMAGE_TAG}
    env_file: $WORKDIR/rehearsal.env
    tmpfs:
      - /tmp/mix_pubsub:mode=0777
    ports:
      - "127.0.0.1:$PORT:4000"
    volumes:
      - app_uploads:/app/priv/static/uploads
      - app_db:/app/priv/db
    environment:
      PHX_HOST: 127.0.0.1
      SCHEME: http
      PORT: 4000
      TENANT_BASE_HOST: soundbored.app
      SOUNDBOARD_DEFAULT_STORAGE_BYTES: 2147483648

volumes:
  app_uploads:
  app_db:
EOF

SECRET_KEY_BASE="$(openssl rand -hex 48)"
cat >"$WORKDIR/rehearsal.env" <<EOF
DISCORD_TOKEN=$DISCORD_TOKEN
DISCORD_CLIENT_ID=$DISCORD_CLIENT_ID
DISCORD_CLIENT_SECRET=${DISCORD_CLIENT_SECRET:-}
SECRET_KEY_BASE=$SECRET_KEY_BASE
AUTO_JOIN=false
EOF

# The guild env makes the migration backfill deterministic: sounds land on a
# known guild id instead of depending on how many guilds the bot is in.
if [ "$SEEDED" = 1 ]; then
  printf 'SOUNDBOARD_DEFAULT_GUILD_ID=%s\n' "$REHEARSAL_GUILD_ID" >>"$WORKDIR/rehearsal.env"
fi

cat >"$WORKDIR/flow.mjs" <<'EOF'
import { chromium } from "@playwright/test";

const base = process.env.BASE_URL;
const email = process.env.TEST_DISCORD_EMAIL;
const password = process.env.TEST_DISCORD_PASSWORD;
const soundsDir = process.env.SOUNDS_DIR;
const expectUploads = process.argv[2] === "upload";

const browser = await chromium.launch();
const page = await browser.newPage();

// Sign in through the real Discord OAuth flow.
await page.goto(`${base}/`);
await page.getByRole("link", { name: /sign in/i }).click();
await page.waitForURL(/discord\.com/);
await page.locator('input[name="email"]').fill(email);
await page.locator('input[name="password"]').fill(password);
await page.locator('button[type="submit"]').first().click();
// Consent screen appears on first authorize only; tolerate both paths.
const consent = page.locator('button:has-text("Authorize")');
if (await consent.count()) await consent.first().click();
await page.waitForURL(`${base}/**`);

if (expectUploads) {
  for (const name of ["rehearsal-one.mp3", "rehearsal-two.mp3"]) {
    await page.locator('input[type="file"]').setInputFiles(`${soundsDir}/${name}`);
    await page.getByText(name).first().waitFor({ timeout: 30_000 });
  }
  console.log("uploaded: rehearsal-one.mp3,rehearsal-two.mp3");
} else {
  for (const name of ["rehearsal-one.mp3", "rehearsal-two.mp3"]) {
    await page.getByText(name).first().waitFor({ timeout: 30_000 });
  }
  // The signed-in user survived the upgrade.
  const navbar = await page.locator("header").innerText();
  if (!/owner|e2e|user/i.test(navbar)) throw new Error("signed-in user missing after upgrade");
  // Join/leave settings surface still renders per guild.
  await page.goto(`${base}/settings`);
  await page.getByText(/join|leave/i).first().waitFor({ timeout: 15_000 });
  console.log("asserted: sounds, user, and settings survived the upgrade");
}

await browser.close();
EOF

cp test/fixtures/* "$WORKDIR/" 2>/dev/null || true
mkdir -p "$WORKDIR/sounds"
for i in 1 2; do
  cp "$(ls test/fixtures/*.mp3 2>/dev/null | head -1)" "$WORKDIR/sounds/rehearsal-$i.mp3"
done

cd "$WORKDIR"

boot() {
  SOUNDBORED_IMAGE_TAG="$1" docker compose -p "$PROJECT" up -d
  for i in $(seq 1 60); do
    curl -sf "$BASE_URL/" >/dev/null && break
    [ "$i" = 60 ] && { docker logs "$(docker compose -p "$PROJECT" ps -qa app | head -1)" 2>&1 | grep -v WARNING | tail -40 >"$WORKDIR/boot-failure.log"; fail "app never became reachable on :$PORT (logs: $WORKDIR/boot-failure.log)"; }
    sleep 2
  done
}

log "Booting the pre-upgrade image ($OLD_IMAGE)"
boot "$OLD_IMAGE"

if [ "$SEEDED" = 1 ]; then
  log "Seeding user, token, sounds, and join setting into the old image"
  KEY1="$(new_uuid).mp3"
  KEY2="$(new_uuid).mp3"
  TOKEN_HASH="$(sha256 "$RAW_TOKEN")"

  cat >"$WORKDIR/seed.sql" <<EOF
INSERT INTO users (discord_id, username, avatar, inserted_at, updated_at)
  VALUES ('$DISCORD_ID', 'rehearsal-user', NULL, '$SEED_DATE', '$SEED_DATE');

INSERT INTO api_tokens (user_id, token_hash, label, revoked_at, last_used_at, inserted_at, updated_at)
  VALUES ((SELECT id FROM users WHERE discord_id = '$DISCORD_ID'), '$TOKEN_HASH', 'rehearsal',
          NULL, NULL, '$SEED_DATE', '$SEED_DATE');

INSERT INTO sounds (filename, storage_key, source_type, volume, user_id, inserted_at, updated_at)
  VALUES
    ('rehearsal-one.mp3', '$KEY1', 'local', 1.0, (SELECT id FROM users WHERE discord_id = '$DISCORD_ID'), '$SEED_DATE', '$SEED_DATE'),
    ('rehearsal-two.mp3', '$KEY2', 'local', 1.0, (SELECT id FROM users WHERE discord_id = '$DISCORD_ID'), '$SEED_DATE', '$SEED_DATE');

INSERT INTO user_sound_settings (user_id, sound_id, is_join_sound, is_leave_sound, inserted_at, updated_at)
  SELECT user_id, id, 1, 0, '$SEED_DATE', '$SEED_DATE' FROM sounds WHERE filename = 'rehearsal-one.mp3';
EOF

  docker run --rm --volumes-from "$(app_ctr)" -v "$WORKDIR:/rehearsal" alpine sh -c "
    cp /rehearsal/sounds/rehearsal-1.mp3 /app/priv/static/uploads/$KEY1 &&
    cp /rehearsal/sounds/rehearsal-2.mp3 /app/priv/static/uploads/$KEY2
  "
  docker run --rm -u 0 -i --volumes-from "$(app_ctr)" keinos/sqlite3 \
    sqlite3 /app/priv/db/soundboard_prod.db <"$WORKDIR/seed.sql"

  # Stop the app so the snapshot and the diff baseline are consistent.
  docker compose -p "$PROJECT" stop app

  dump_state >"$WORKDIR/pre-dump.txt"
  checksum_files >"$WORKDIR/pre-checksums.txt"
else
  log "Signing in and uploading two sounds"
  node flow.mjs upload
fi

log "Snapshotting volumes"
for vol in app_uploads app_db; do
  docker run --rm --volumes-from "$(app_ctr)" -v "$WORKDIR:/backup" alpine \
    tar czf "/backup/$vol.tgz" -C / "$([ "$vol" = app_uploads ] && echo app/priv/static/uploads || echo app/priv/db)"
done
ls -la "$WORKDIR"/*.tgz

log "Swapping to the multi-tenant image ($NEW_IMAGE) and rebooting"
docker compose -p "$PROJECT" down
boot "$NEW_IMAGE"

if [ "$SEEDED" = 1 ]; then
  log "Asserting sounds, users, and settings survived"

  dump_state >"$WORKDIR/post-dump.txt"
  diff "$WORKDIR/pre-dump.txt" "$WORKDIR/post-dump.txt" >/dev/null \
    || fail "user, token, sound, or setting rows changed across the upgrade (diff $WORKDIR/pre-dump.txt $WORKDIR/post-dump.txt)"
  echo "ok: user, token, sound, and setting rows are byte-identical across the upgrade"

  checksum_files >"$WORKDIR/post-checksums.txt"
  diff "$WORKDIR/pre-checksums.txt" "$WORKDIR/post-checksums.txt" >/dev/null \
    || fail "uploaded sound files changed across the upgrade"
  echo "ok: uploaded sound files are byte-identical across the upgrade"

  # The backfill must scope legacy sounds to the configured guild with
  # byte_size 0 so no storage cap can block them. Join settings follow.
  bad="$(db "SELECT COUNT(*) FROM sounds
    WHERE filename LIKE 'rehearsal-%'
      AND (guild_id IS NULL OR guild_id != '$REHEARSAL_GUILD_ID' OR byte_size != 0);")" \
    || fail "backfill query failed"
  [ "$bad" = "0" ] || fail "legacy sound backfill wrong ($bad rows off)"
  bad="$(db "SELECT COUNT(*) FROM user_sound_settings
    WHERE sound_id IN (SELECT id FROM sounds WHERE filename LIKE 'rehearsal-%')
      AND (guild_id IS NULL OR guild_id != '$REHEARSAL_GUILD_ID');")" \
    || fail "setting backfill query failed"
  [ "$bad" = "0" ] || fail "join-sound setting backfill wrong ($bad rows off)"
  echo "ok: legacy sounds and settings backfilled into the default guild, byte_size 0"

  # The seeded token still authenticates, and the sounds are listable and
  # playable through the API surface.
  api_code="$(curl -s -o "$WORKDIR/api-sounds.json" -w '%{http_code}' \
    -H "Authorization: Bearer $RAW_TOKEN" "$BASE_URL/api/sounds")" \
    || fail "GET /api/sounds request failed"
  [ "$api_code" = 200 ] || fail "GET /api/sounds returned $api_code ($(cat "$WORKDIR/api-sounds.json" 2>/dev/null))"
  grep -q rehearsal-one.mp3 "$WORKDIR/api-sounds.json" || fail "API does not list rehearsal-one.mp3"
  grep -q rehearsal-two.mp3 "$WORKDIR/api-sounds.json" || fail "API does not list rehearsal-two.mp3"
  echo "ok: seeded API token authenticates and lists both sounds"

  ids="$(grep -o '"id": *"\?[0-9]*' "$WORKDIR/api-sounds.json" | grep -o '[0-9]*' | sort -u)"
  [ "$(printf '%s\n' "$ids" | grep -c .)" = 2 ] || fail "expected two sound ids from the API"
  for id in $ids; do
    play_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $RAW_TOKEN" "$BASE_URL/api/sounds/$id/play")" \
      || fail "play request for sound $id failed"
    [ "$play_code" = 202 ] || fail "play for sound $id returned $play_code"
  done
  echo "ok: both sounds playable through the API"

  code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/")" || fail "GET / request failed"
  case "$code" in 200|302|307) ;; *) fail "GET / returned $code after upgrade" ;; esac
  echo "ok: app serves after the upgrade"

  echo "asserted: user, token, both sounds and their files, and the join setting survived the upgrade"
else
  log "Asserting sounds, users, and settings survived"
  node flow.mjs assert
fi

log "Cleaning up"
docker compose -p "$PROJECT" down -v >/dev/null 2>&1
trap - EXIT
echo "REHEARSAL PASSED. Artifacts in $WORKDIR (volume snapshots, dumps, checksums)."
