<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

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
- Pre-commit: `mix precommit` — runs format, credo (strict), and the test suite; run after every change.
- Coverage: `mix coveralls` or `mix coveralls.html` (outputs to `cover/`).
- Lint/format: `mix credo --strict` and `mix format`.
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

## Issue Tracking (Beads)
- Issues live in `.beads/issues.jsonl`; use the `bd` CLI (already vendored) to manage them.
- Common commands: `bd list`, `bd show <id>`, `bd create "Title" --body "details"`, `bd update <id> --status in-progress|done`.
- Keep IDs in commits/PRs when relevant; prefer brief, actionable titles and a clear definition of done in the body.
- No extra setup needed locally; bd.sock is already present in the repo.

## Security & Configuration Tips
- Secrets via `.env` (see `.env.example`): Discord tokens, API token, `PHX_HOST`, `SCHEME`.
- Do not commit real secrets; prefer Docker env files in development and deployment.
- For production, keep secrets in `.env` and run the single compose stack; integrate your own reverse proxy/load balancer as needed.



## MCP Agent Mail: coordination for multi-agent workflows

What it is
- A mail-like layer that lets coding agents coordinate asynchronously via MCP tools and resources.
- Provides identities, inbox/outbox, searchable threads, and advisory file reservations, with human-auditable artifacts in Git.

Why it's useful
- Prevents agents from stepping on each other with explicit file reservations (leases) for files/globs.
- Keeps communication out of your token budget by storing messages in a per-project archive.
- Offers quick reads (`resource://inbox/...`, `resource://thread/...`) and macros that bundle common flows.

How to use effectively
1) Same repository
   - Register an identity: call `ensure_project`, then `register_agent` using this repo's absolute path as `project_key`.
   - Reserve files before you edit: `file_reservation_paths(project_key, agent_name, ["src/**"], ttl_seconds=3600, exclusive=true)` to signal intent and avoid conflict.
   - Communicate with threads: use `send_message(..., thread_id="FEAT-123")`; check inbox with `fetch_inbox` and acknowledge with `acknowledge_message`.
   - Read fast: `resource://inbox/{Agent}?project=<abs-path>&limit=20` or `resource://thread/{id}?project=<abs-path>&include_bodies=true`.
   - Tip: set `AGENT_NAME` in your environment so the pre-commit guard can block commits that conflict with others' active exclusive file reservations.

2) Across different repos in one project (e.g., Next.js frontend + FastAPI backend)
   - Option A (single project bus): register both sides under the same `project_key` (shared key/path). Keep reservation patterns specific (e.g., `frontend/**` vs `backend/**`).
   - Option B (separate projects): each repo has its own `project_key`; use `macro_contact_handshake` or `request_contact`/`respond_contact` to link agents, then message directly. Keep a shared `thread_id` (e.g., ticket key) across repos for clean summaries/audits.

Macros vs granular tools
- Prefer macros when you want speed or are on a smaller model: `macro_start_session`, `macro_prepare_thread`, `macro_file_reservation_cycle`, `macro_contact_handshake`.
- Use granular tools when you need control: `register_agent`, `file_reservation_paths`, `send_message`, `fetch_inbox`, `acknowledge_message`.

Common pitfalls
- "from_agent not registered": always `register_agent` in the correct `project_key` first.
- "FILE_RESERVATION_CONFLICT": adjust patterns, wait for expiry, or use a non-exclusive reservation when appropriate.
- Auth errors: if JWT+JWKS is enabled, include a bearer token with a `kid` that matches server JWKS; static bearer is used only when JWT is disabled.



## Integrating with Beads (dependency-aware task planning)

Beads provides a lightweight, dependency-aware issue database and a CLI (`bd`) for selecting "ready work," setting priorities, and tracking status. It complements MCP Agent Mail's messaging, audit trail, and file-reservation signals. Project: [steveyegge/beads](https://github.com/steveyegge/beads)

Recommended conventions
- **Single source of truth**: Use **Beads** for task status/priority/dependencies; use **Agent Mail** for conversation, decisions, and attachments (audit).
- **Shared identifiers**: Use the Beads issue id (e.g., `bd-123`) as the Mail `thread_id` and prefix message subjects with `[bd-123]`.
- **Reservations**: When starting a `bd-###` task, call `file_reservation_paths(...)` for the affected paths; include the issue id in the `reason` and release on completion.

Typical flow (agents)
1) **Pick ready work** (Beads)
   - `bd ready --json` → choose one item (highest priority, no blockers)
2) **Reserve edit surface** (Mail)
   - `file_reservation_paths(project_key, agent_name, ["src/**"], ttl_seconds=3600, exclusive=true, reason="bd-123")`
3) **Announce start** (Mail)
   - `send_message(..., thread_id="bd-123", subject="[bd-123] Start: <short title>", ack_required=true)`
4) **Work and update**
   - Reply in-thread with progress and attach artifacts/images; keep the discussion in one thread per issue id
5) **Complete and release**
   - `bd close bd-123 --reason "Completed"` (Beads is status authority)
   - `release_file_reservations(project_key, agent_name, paths=["src/**"])`
   - Final Mail reply: `[bd-123] Completed` with summary and links

Mapping cheat-sheet
- **Mail `thread_id`** ↔ `bd-###`
- **Mail subject**: `[bd-###] …`
- **File reservation `reason`**: `bd-###`
- **Commit messages (optional)**: include `bd-###` for traceability

Event mirroring (optional automation)
- On `bd update --status blocked`, send a high-importance Mail message in thread `bd-###` describing the blocker.
- On Mail "ACK overdue" for a critical decision, add a Beads label (e.g., `needs-ack`) or bump priority to surface it in `bd ready`.

Pitfalls to avoid
- Don't create or manage tasks in Mail; treat Beads as the single task queue.
- Always include `bd-###` in message `thread_id` to avoid ID drift across tools.

