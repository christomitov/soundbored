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

# Run migrations
echo "Running database migrations..."
mix ecto.migrate

# Start Phoenix server in foreground
# Using exec ensures proper signal handling and process management
echo "Starting Phoenix server..."
exec mix phx.server
