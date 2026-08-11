#!/bin/sh

NEW_DB="/app/priv/db/soundboard_prod.db"
mkdir -p /app/priv/db

# Migrate database from old location (inside uploads) to priv/db
OLD_DB="/app/priv/static/uploads/soundboard_prod.db"
if [ -f "$OLD_DB" ] && [ ! -f "$NEW_DB" ]; then
  echo "Migrating database from uploads to priv/db..."
  cp "$OLD_DB" "$NEW_DB"
  for wal in "$OLD_DB-shm" "$OLD_DB-wal"; do
    [ -f "$wal" ] && cp "$wal" "/app/priv/db/$(basename "$wal")"
  done
fi

ytdlp_works() {
  [ -n "$1" ] && [ -x "$1" ] && "$1" --version >/dev/null 2>&1
}

# Ensure yt-dlp exists. Prefer YTDLP_PATH, else a known path on the writable db volume
# (compose mounts are often read-only at /app).
# On Alpine/musl we install the Python zipapp (needs python3), not glibc native builds.
ensure_ytdlp() {
  if ytdlp_works "${YTDLP_PATH:-}"; then
    echo "Using yt-dlp at $YTDLP_PATH"
    export YTDLP_PATH
    return 0
  fi

  if command -v yt-dlp >/dev/null 2>&1 && ytdlp_works "$(command -v yt-dlp)"; then
    YTDLP_PATH="$(command -v yt-dlp)"
    export YTDLP_PATH
    echo "Using yt-dlp from PATH: $YTDLP_PATH"
    return 0
  fi

  YTDLP_PATH="${YTDLP_PATH:-/app/priv/db/bin/yt-dlp}"
  export YTDLP_PATH
  mkdir -p "$(dirname "$YTDLP_PATH")"

  if ytdlp_works "$YTDLP_PATH"; then
    echo "Using managed yt-dlp at $YTDLP_PATH"
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "WARNING: python3 is required for yt-dlp on Alpine; install python3"
    return 1
  fi

  # Universal Python zipapp — portable across musl/glibc
  URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"

  echo "yt-dlp not found or not runnable; downloading ${URL} -> ${YTDLP_PATH}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$YTDLP_PATH" "$URL" || {
      echo "WARNING: failed to download yt-dlp with curl"
      return 1
    }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$YTDLP_PATH" "$URL" || {
      echo "WARNING: failed to download yt-dlp with wget"
      return 1
    }
  else
    echo "WARNING: curl/wget missing; cannot download yt-dlp"
    return 1
  fi

  chmod a+rx "$YTDLP_PATH"
  # Ensure zipapp shebang can find python3
  if head -c 2 "$YTDLP_PATH" | grep -q '#!'; then
    sed -i '1s|^#!.*|#!/usr/bin/env python3|' "$YTDLP_PATH" 2>/dev/null || true
  fi

  if ytdlp_works "$YTDLP_PATH"; then
    echo "yt-dlp ready at $YTDLP_PATH ($("$YTDLP_PATH" --version))"
    return 0
  fi

  echo "WARNING: downloaded yt-dlp is not runnable"
  return 1
}

ensure_ytdlp || true

# Run migrations
echo "Running database migrations..."
mix ecto.migrate

# Start Phoenix server in foreground
# Using exec ensures proper signal handling and process management
echo "Starting Phoenix server..."
exec mix phx.server
