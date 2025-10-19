# Repository Guidelines

## Project Structure & Module Organization
- Source: `lib/soundboard` (core), `lib/soundboard_web` (Phoenix web, LiveView, controllers, components).
- Frontend assets: `assets/js`, `assets/css`, `assets/tailwind.config.js`.
- Config and priv: `config/`, `priv/` (static, migrations, etc.).
- Tests: `test/` mirroring lib; helpers in `test/support`.

## Build, Test, and Development Commands
- Setup: `mix setup` — fetch deps, create/migrate DB, install/build assets.
- Run dev server: `mix phx.server` (or `iex -S mix phx.server`).
- Tests: `mix test` — includes DB setup via alias.
- Coverage: `mix coveralls` or `mix coveralls.html` (outputs to `cover/`).
- Lint/format: `mix credo` and `mix format`.
- Assets prod build: `mix assets.deploy`.
- Docker local: `docker compose up` (env from `.env`).

## Coding Style & Naming Conventions
- Elixir style: 2‑space indent; run `mix format` before committing.
- Modules: `Soundboard.*` and `SoundboardWeb.*`; filenames snake_case.
- Functions/vars: snake_case; constants via module attributes.
- Components/LiveViews live under `lib/soundboard_web/{components,live}` with descriptive names (e.g., `favorites_live.ex`).

## Testing Guidelines
- Framework: ExUnit with helpers in `test/support` (`ConnCase`, `DataCase`).
- Naming: mirror module under `test/…/*_test.exs` (e.g., `stats_test.exs`).
- Run selective: `mix test test/soundboard/stats_test.exs:42`.
- Coverage: aim >90% for new code; add unit tests for contexts and LiveView interaction where feasible.

## Commit & Pull Request Guidelines
- Commits: imperative mood, concise (e.g., "Fix audio playback path"). Group related changes.
- PRs: clear description, linked issues, screenshots for UI changes, reproduction steps, and risk/rollback notes.
- Checks: ensure `mix test`, `mix credo`, and `mix format --check-formatted` pass.

## Security & Configuration Tips
- Secrets via `.env` (see `.env.example`): Discord tokens, API token, `PHX_HOST`, `SCHEME`.
- Do not commit real secrets; prefer Docker env files in development and deployment.
- For production, keep secrets in `.env` and run the single compose stack; integrate your own reverse proxy/load balancer as needed.
