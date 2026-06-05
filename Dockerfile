# syntax=docker/dockerfile:1
FROM elixir:1.20.0-otp-27-alpine AS build

ARG MIX_ENV=prod

ENV MIX_ENV=$MIX_ENV \
    MIX_HOME=/app/.mix \
    HEX_HOME=/app/.hex \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8

RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    apk add --no-cache \
      git \
      make \
      build-base \
      rust=1.96.0-r0 \
      cargo=1.96.0-r0

WORKDIR /app
COPY --exclude=entrypoint.sh . .

# Install hex/rebar and fetch locked dependencies.
RUN mkdir -p /app/.mix /app/.hex && \
    mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

RUN export SKIP_RUNTIME_CONFIG=1 && \
    mix assets.setup && \
    mix compile && \
    mix assets.deploy && \
    cd deps/eda/native/eda_dave && \
    cargo build --release && \
    mkdir -p /app/_build/${MIX_ENV}/lib/eda/priv/native && \
    cp target/release/libeda_dave.so /app/_build/${MIX_ENV}/lib/eda/priv/native/eda_dave.so

FROM elixir:1.20.0-otp-27-alpine

ENV MIX_ENV=prod \
    MIX_HOME=/app/.mix \
    HEX_HOME=/app/.hex \
    HOME=/app \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8

RUN apk add --no-cache \
    ffmpeg \
    git \
    libstdc++

WORKDIR /app
COPY --from=build /app .
RUN chmod -R a+rX /app/.mix /app/.hex

COPY entrypoint.sh /app
RUN chmod a+x /app/entrypoint.sh

VOLUME ["/app/priv/static/uploads", "/app/priv/db"]
EXPOSE 4000
ENTRYPOINT ["/app/entrypoint.sh"]
