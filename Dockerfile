FROM erlang:27-alpine AS build

ARG MIX_ENV=prod

ENV MIX_ENV=$MIX_ENV \
    MIX_HOME=/app/.mix \
    HEX_HOME=/app/.hex \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 \
    ELIXIR_VERSION="v1.18.0"

# Install dependencies required for building ffmpeg and system utilities
RUN apk add --no-cache \
    ffmpeg \
    bash \
    curl \
    make \
    git

# Verify shell environment
RUN which bash && \
    which sh && \
    echo "Shell verification complete" && \
    bash --version

# Install Elixir
RUN set -xe \
    && ELIXIR_DOWNLOAD_URL="https://github.com/elixir-lang/elixir/archive/${ELIXIR_VERSION}.tar.gz" \
    && ELIXIR_DOWNLOAD_SHA256="f29104ae5a0ea78786b5fb96dce0c569db91df5bd1d3472b365dc2ea14ea784f" \
    && curl -fSL -o elixir-src.tar.gz $ELIXIR_DOWNLOAD_URL \
    && echo "$ELIXIR_DOWNLOAD_SHA256  elixir-src.tar.gz" | sha256sum -c - \
    && mkdir -p /usr/local/src/elixir \
    && tar -xzC /usr/local/src/elixir --strip-components=1 -f elixir-src.tar.gz \
    && rm elixir-src.tar.gz \
    && cd /usr/local/src/elixir \
    && make install clean \
    && find /usr/local/src/elixir/ -type f -not -regex "/usr/local/src/elixir/lib/[^\/]*/lib.*" -exec rm -rf {} + \
    && find /usr/local/src/elixir/ -type d -depth -empty -delete

WORKDIR /app
COPY . .

# Install hex and rebar and get dependencies
RUN mkdir -p /app/.mix /app/.hex && \
    mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

RUN chmod -R a+rwX /app/.mix /app/.hex

RUN bash -c '\
    if [ ! -f /app/.secret_key_base ]; then \
        generated_key=$(mix phx.gen.secret); \
        echo "$generated_key" > /app/.secret_key_base; \
    fi && \
    chmod 444 /app/.secret_key_base && \
    echo "Prepared SECRET_KEY_BASE file (length: $(wc -c < /app/.secret_key_base) bytes)"'

RUN SECRET_KEY_BASE=dummy-build-secret mix setup && \
    SECRET_KEY_BASE=dummy-build-secret mix assets.deploy

FROM erlang:27-alpine AS runtime

ENV MIX_ENV=prod \
    MIX_HOME=/app/.mix \
    HEX_HOME=/app/.hex \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8

RUN apk add --no-cache \
    ffmpeg \
    bash \
    curl \
    git

WORKDIR /app
COPY --from=build /app /app
COPY --from=build /usr/local /usr/local
RUN chmod -R a+rwX /app/.mix /app/.hex

RUN cat <<'EOF' > /app/entrypoint.sh
#!/bin/bash
set -e

# Enable command tracing for debugging
set -x

# Debug information
echo "=== Starting entrypoint script ==="
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -la
echo "Environment variables:"
env | grep -v "SECRET"

# Prepare temporary directories for Phoenix PubSub/etc.
export TMPDIR=${TMPDIR:-/tmp/mix_pubsub}
mkdir -p "$TMPDIR"
chmod 1777 "$TMPDIR" || true

# Set HOME so Mix uses a consistent path when running as a non-root user
export HOME=${HOME:-/app}

# Set up SECRET_KEY_BASE
if [ -n "${SECRET_KEY_BASE:-}" ]; then
  echo "SECRET_KEY_BASE provided via environment (length: ${#SECRET_KEY_BASE} bytes)"
elif [ -r /app/.secret_key_base ]; then
  export SECRET_KEY_BASE=$(cat /app/.secret_key_base)
  echo "Secret key base is configured from file (length: ${#SECRET_KEY_BASE} bytes)"
else
  echo "SECRET_KEY_BASE is not set and /app/.secret_key_base is unreadable" >&2
  exit 1
fi

# Run migrations
echo "Running database migrations..."
mix ecto.migrate

# Start Phoenix server in foreground
# Using exec ensures proper signal handling and process management
echo "Starting Phoenix server..."
exec mix phx.server
EOF

RUN chmod +x /app/entrypoint.sh

SHELL ["/bin/bash", "-c"]
ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh"]
