# syntax=docker/dockerfile:1

# Build whisper.cpp first
FROM alpine:3.19 AS whisper-build

RUN apk add --no-cache \
    git \
    cmake \
    make \
    g++ \
    sdl2-dev

WORKDIR /whisper

# Clone and build whisper.cpp
RUN git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git . && \
    cmake -B build && \
    cmake --build build --config Release -j$(nproc) && \
    cp build/bin/main /whisper/whisper-cli

# Download the base.en model (small and fast for English)
RUN apk add --no-cache curl && \
    curl -L -o models/ggml-base.en.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# Elixir build stage
FROM elixir:1.19-alpine AS build

ARG MIX_ENV=prod

ENV MIX_ENV=$MIX_ENV \
    MIX_HOME=/app/.mix \
    HEX_HOME=/app/.hex \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8

RUN apk add --no-cache \
    git \
    make

WORKDIR /app
COPY . .

# Install hex and rebar and get dependencies
RUN mkdir -p /app/.mix /app/.hex && \
    mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get

RUN export SKIP_RUNTIME_CONFIG=1 && \
    mix assets.setup && \
    mix compile && \
    mix assets.deploy

# Runtime stage
FROM elixir:1.19-alpine

ENV MIX_ENV=prod \
    MIX_HOME=/app/.mix \
    HEX_HOME=/app/.hex \
    HOME=/app \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8

# Runtime dependencies including whisper.cpp requirements
RUN apk add --no-cache \
    ffmpeg \
    git \
    libstdc++ \
    libgcc

WORKDIR /app

# Copy whisper.cpp binary and model from build stage
COPY --from=whisper-build /whisper/whisper-cli /usr/local/bin/whisper
COPY --from=whisper-build /whisper/models/ggml-base.en.bin /usr/local/share/whisper/ggml-base.en.bin

# Copy Elixir app
COPY --from=build /app .
RUN chmod -R a+rX /app/.mix /app/.hex

COPY entrypoint.sh /app
RUN chmod a+x /app/entrypoint.sh

VOLUME ["/app/priv/static/uploads"]
EXPOSE 4000
ENTRYPOINT ["/app/entrypoint.sh"]
