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
#   NEW_IMAGE (optional, default christom/soundbored:multi-tenant)
#
# Usage: deploy/upgrade-rehearsal.sh
set -euo pipefail

OLD_IMAGE="christom/soundbored:latest"
NEW_IMAGE="${NEW_IMAGE:-christom/soundbored:multi-tenant}"
PROJECT="soundbored-rehearsal"
PORT="${REHEARSAL_PORT:-4100}"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/soundbored-rehearsal.XXXXXX")"
COMPOSE_FILE="$WORKDIR/docker-compose.yml"
BASE_URL="http://127.0.0.1:$PORT"

log() { printf '\n=== %s ===\n' "$1"; }
fail() { printf 'REHEARSAL FAILED: %s\n' "$1" >&2; exit 1; }

for var in DISCORD_CLIENT_ID DISCORD_TOKEN TEST_DISCORD_EMAIL TEST_DISCORD_PASSWORD; do
  [ -n "${!var:-}" ] || fail "$var must be set (see header)"
done
command -v docker >/dev/null || fail "docker not found"
node --version >/dev/null 2>&1 || fail "node not found (needed for Playwright)"

log "Staging rehearsal stack in $WORKDIR"
cd "$(dirname "$0")/.."

# Rehearsal compose: the prod image shape (same volumes, entrypoint, user) on a
# local port, without the Coolify proxy. SCHEME is http locally.
cat >"$COMPOSE_FILE" <<EOF
services:
  app:
    image: \${SOUNDBORED_IMAGE_TAG}
    env_file: $WORKDIR/rehearsal.env
    user: "9999:9999"
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

cat >"$WORKDIR/rehearsal.env" <<EOF
DISCORD_TOKEN=$DISCORD_TOKEN
DISCORD_CLIENT_ID=$DISCORD_CLIENT_ID
DISCORD_CLIENT_SECRET=${DISCORD_CLIENT_SECRET:-}
AUTO_JOIN=false
EOF

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

log "Pulling and booting the pre-upgrade image ($OLD_IMAGE)"
SOUNDBORED_IMAGE_TAG="$OLD_IMAGE" docker compose -p "$PROJECT" up -d
for i in $(seq 1 60); do
  curl -sf "$BASE_URL/" >/dev/null && break
  [ "$i" = 60 ] && fail "app never became reachable on :$PORT"
  sleep 2
done

log "Signing in and uploading two sounds"
node flow.mjs upload

log "Snapshotting volumes"
app_ctr="$(docker compose -p "$PROJECT" ps -q app)"
for vol in app_uploads app_db; do
  docker run --rm --volumes-from "$app_ctr" -v "$WORKDIR:/backup" alpine \
    tar czf "/backup/$vol.tgz" -C / "$([ "$vol" = app_uploads ] && echo app/priv/static/uploads || echo app/priv/db)"
done
ls -la "$WORKDIR"/*.tgz

log "Swapping to the multi-tenant image ($NEW_IMAGE) and rebooting"
docker compose -p "$PROJECT" down
SOUNDBORED_IMAGE_TAG="$NEW_IMAGE" docker compose -p "$PROJECT" up -d
for i in $(seq 1 60); do
  curl -sf "$BASE_URL/" >/dev/null && break
  [ "$i" = 60 ] && fail "upgraded app never became reachable on :$PORT"
  sleep 2
done

log "Asserting sounds, users, and settings survived"
node flow.mjs assert

log "Cleaning up"
docker compose -p "$PROJECT" down -v
echo "REHEARSAL PASSED. Artifacts in $WORKDIR (volume snapshots, logs)."
