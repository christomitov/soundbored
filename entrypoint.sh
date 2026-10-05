#!/bin/sh

# Migrate database from old location (inside uploads) to priv/db
NEW_DB="/app/priv/db/soundboard_prod.db"
OLD_DB="/app/priv/static/uploads/soundboard_prod.db"
if [ -f "$OLD_DB" ] && [ ! -f "$NEW_DB" ]; then
  echo "Migrating database from uploads to priv/db..."
  cp "$OLD_DB" "$NEW_DB"
  for wal in "$OLD_DB-shm" "$OLD_DB-wal"; do
    [ -f "$wal" ] && cp "$wal" "/app/priv/db/$(basename "$wal")"
  done
fi

# The compose file mounts named volumes at /app/priv/db and /app/priv/static/uploads.
# Docker populates fresh volumes with the image's root ownership, so a first
# boot cannot create the database when the app runs unprivileged. Fix the
# ownership when the container starts as root, then run as the app user.
if [ "$(id -u)" = "0" ] && command -v su-exec >/dev/null 2>&1; then
  chown -R 9999:9999 /app/priv/db /app/priv/static/uploads
  echo "Running database migrations..."
  su-exec 9999:9999 mix ecto.migrate

  # Start Phoenix server in foreground
  # Using exec ensures proper signal handling and process management
  echo "Starting Phoenix server..."
  exec su-exec 9999:9999 mix phx.server
else
  # Run migrations
  echo "Running database migrations..."
  mix ecto.migrate

  # Start Phoenix server in foreground
  # Using exec ensures proper signal handling and process management
  echo "Starting Phoenix server..."
  exec mix phx.server
fi
