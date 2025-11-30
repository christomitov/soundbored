# Project Context

## Purpose
Soundbored is a self-hosted Discord soundboard that lets users upload, organize, and trigger sounds in Discord voice channels from a Phoenix LiveView UI, bot commands, or an authenticated API. Goals: unlimited playback with real-time updates, easy self-hosting (Docker), and optional multi-tenant SaaS/pro mode.

## Tech Stack
- Elixir 1.19 with Phoenix 1.8 and LiveView 1.1
- Ecto with SQLite3 by default; Postgres adapter when `SOUNDBORED_DB=pro/postgres` (Pro/multi-tenant)
- Bandit HTTP server; Phoenix PubSub for realtime
- Nostrum for Discord bot/voice; Ueberauth + ueberauth_discord for auth
- Frontend: Tailwind CSS, esbuild, Heroicons (assets under `assets/`)
- Tooling: Credo (strict), ExUnit, ExCoveralls, Mock; Docker images published to `christom/soundbored`

## Project Conventions

### Code Style
- 2-space indent; run `mix format` (HEEx via Phoenix.LiveView.HTMLFormatter) before committing
- Lint with `mix credo --strict`; keep functions small and purposeful
- Naming: snake_case for vars/functions, PascalCase modules under `Soundboard.*` and `SoundboardWeb.*`
- Keep contexts isolated from web layer; place LiveViews/components under `lib/soundboard_web`
- Frontend uses Tailwind utilities; keep assets organized in `assets/js` and `assets/css`

### Architecture Patterns
- Context-based design: Accounts, Sounds/Tags/Favorites, Stats, etc. live in `lib/soundboard/`
- LiveViews/components/controllers in `lib/soundboard_web`; API controllers handle playback/auth endpoints
- GenServers handle Discord bot commands and voice playback (`SoundboardWeb.DiscordHandler`, `SoundboardWeb.AudioPlayer`)
- PubSub broadcasts for uploads, plays, presence; caching/invalidation around audio files
- Multi-tenant routing and guild-to-tenant isolation for Pro builds; runtime repo adapter selection via env
- Build/deploy via Mix aliases (`mix setup`, `mix assets.deploy`); Docker entrypoint uses `.env` configuration

### Testing Strategy
- ExUnit with helpers in `test/support` (`ConnCase`, `DataCase`); tests live under `test/**/*_test.exs`
- `mix test` sets up DB via aliases; prefer LiveView interaction tests for UI flows
- Coverage via ExCoveralls (`mix coveralls*`); aim >90% for new code
- Mock external Discord interactions with `Mock`; keep tests deterministic and isolated

### Git Workflow
- Work on feature branches off `main`; open PRs with clear descriptions and screenshots for UI changes
- Commits in imperative mood (e.g., “Fix audio playback path”)
- Before PR: run `mix test`, `mix credo --strict`, `mix format --check-formatted`
- CI runs tests/coverage/credo; coverage reported via Coveralls

## Domain Context
- Sound uploads live under `priv/static/uploads`; supports uploads and URL-based sounds with tags and stats
- Bot joins/leaves Discord voice channels to play sounds; presence and recent plays tracked for stats
- Favorites, random play, join/leave sounds, and per-user settings exposed in UI
- API endpoints secured by bearer tokens (legacy `API_TOKEN` and DB-backed tokens managed in Settings)
- Optional basic auth for UI; CLI companion (`soundbored`) automates API/UI flows
- Pro/SaaS mode adds tenant routing, billing hooks, and guild-to-tenant mapping (see `PRO_README.md`)

## Important Constraints
- Discord intents required: Presence, Server Members, Message Content; permissions: Send Messages, Read History, View Channels, Connect, Speak
- OAuth redirect URLs must match Discord app config; `PHX_HOST` and `SCHEME` must reflect external URL (esp. behind proxies)
- Keep secrets out of git; use `.env`/Docker env (see `.env.example`); `API_TOKEN`/basic auth guard API/UI
- Default DB adapter is SQLite; set `SOUNDBORED_DB=pro` to force Postgres in Pro deployments
- Respect Discord rate limits; voice playback depends on ffmpeg availability (`/usr/bin/ffmpeg` in container)

## External Dependencies
- Discord API/OAuth (bot + login) via Nostrum and Ueberauth Discord
- Database: SQLite by default, Postgres for Pro; ffmpeg required for voice playback
- Coveralls for CI coverage reporting; GitHub Actions for CI/CD; Docker Hub image `christom/soundbored`
