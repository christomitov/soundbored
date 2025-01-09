FROM erlang:27

# Define build arguments
ARG API_TOKEN
ARG DISCORD_CLIENT_ID
ARG DISCORD_CLIENT_SECRET
ARG DISCORD_TOKEN
ARG PHX_HOST
ARG SCHEME
ARG MIX_ENV=prod
ARG SECRET_KEY_BASE
ARG BASIC_AUTH_USERNAME
ARG BASIC_AUTH_PASSWORD

# Set environment variables from build arguments
ENV API_TOKEN=$API_TOKEN \
    DISCORD_CLIENT_ID=$DISCORD_CLIENT_ID \
    DISCORD_CLIENT_SECRET=$DISCORD_CLIENT_SECRET \
    DISCORD_TOKEN=$DISCORD_TOKEN \
    PHX_HOST=$PHX_HOST \
    MIX_ENV=$MIX_ENV \
    SCHEME=$SCHEME \
    BASIC_AUTH_USERNAME=$BASIC_AUTH_USERNAME \
    BASIC_AUTH_PASSWORD=$BASIC_AUTH_PASSWORD \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 \
    ELIXIR_VERSION="v1.18.0"

# Install dependencies required for building ffmpeg
RUN apt-get update && apt-get install -y \
    ffmpeg \
    bash \
    && rm -rf /var/lib/apt/lists/*

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
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

# Generate and store SECRET_KEY_BASE
RUN bash -c '\
    if [ -z "$SECRET_KEY_BASE" ]; then \
        echo "Generating new SECRET_KEY_BASE..."; \
        generated_key=$(mix phx.gen.secret); \
        echo "$generated_key" > /app/.secret_key_base; \
    else \
        echo "Using provided SECRET_KEY_BASE"; \
        echo "$SECRET_KEY_BASE" > /app/.secret_key_base; \
    fi && \
    chmod 600 /app/.secret_key_base && \
    export SECRET_KEY_BASE=$(cat /app/.secret_key_base) && \
    echo "SECRET_KEY_BASE length: ${#SECRET_KEY_BASE} bytes" && \
    mix setup && \
    mix assets.deploy'

# Create an entrypoint script that ensures SECRET_KEY_BASE is set
RUN echo '#!/bin/bash\n\
export SECRET_KEY_BASE=$(cat /app/.secret_key_base)\n\
echo "Using SECRET_KEY_BASE (length: ${#SECRET_KEY_BASE} bytes)"\n\
mix ecto.migrate\n\
mix phx.server' > /app/entrypoint.sh && \
chmod +x /app/entrypoint.sh

SHELL ["/bin/bash", "-c"]
ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh"]