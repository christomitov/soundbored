#!/bin/sh

# Run migrations
echo "Running database migrations..."
mix ecto.migrate

# Start Phoenix server in foreground
# Using exec ensures proper signal handling and process management
echo "Starting Phoenix server..."
exec mix phx.server
