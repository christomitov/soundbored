# Spec: Discord Role-Gated Access

**Status:** Implemented
**Date:** 2026-04-27

---

## Summary

Restrict web access to Discord users who are members of a configured guild **and** hold at least one configured role. Verification happens at OAuth login and is re-checked periodically per session. When unconfigured, behavior is unchanged — anyone who completes Discord OAuth gets in.

---

## Configuration

Three env vars parsed in `config/runtime.exs`:

| Env Var | Type | Default | Description |
|---|---|---|---|
| `DISCORD_REQUIRED_GUILD_ID` | string | `nil` | Guild snowflake ID |
| `DISCORD_REQUIRED_ROLE_IDS` | comma-separated strings | `""` | Role snowflake IDs; user must hold at least one |
| `DISCORD_ROLE_RECHECK_INTERVAL_SECONDS` | integer | `900` | Seconds between role re-checks per session |

Feature is **enabled** only when both `DISCORD_REQUIRED_GUILD_ID` is set and `DISCORD_REQUIRED_ROLE_IDS` is non-empty. Either unset → feature disabled, no role checks performed.

---

## Behavior

| Scenario | Result |
|---|---|
| Feature not configured | Open access — current behavior preserved |
| User authenticates, has a required role | Logged in normally |
| User authenticates, lacks required role | No user record created; redirected to `/` with `"Error signing in"` flash |
| Logged-in user loses required role | At next re-check, session cleared, redirected to `/` |
| Discord API call fails | Fails closed — user denied |

The flash message is intentionally generic to avoid leaking why access was denied.

---

## Architecture

**`Soundboard.Discord.RoleChecker`** (`lib/soundboard/discord/role_checker.ex`)
Wraps `EDA.API.Member.get/2`. `feature_enabled?/0` checks config; `authorized?/1` short-circuits to `true` when disabled, otherwise checks guild role membership. Fails closed on any error or unexpected API response.

**`SoundboardWeb.AuthController`**
The OAuth callback calls `RoleChecker.authorized?/1` before `find_or_create_user`. On success, stores `:user_id` and `:roles_verified_at` in session. On failure, no DB write, generic flash.

**`SoundboardWeb.Plugs.RoleCheck`** (`lib/soundboard_web/plugs/role_check.ex`)
Runs after `ensure_authenticated_user`. Pass-through when: no `current_user`, feature disabled, or `:roles_verified_at` is fresh. Otherwise re-checks via `RoleChecker.authorized?/1` — updates timestamp on success, clears session and halts on failure.

**Router:** New `:require_role_check` pipeline wired into both protected scopes (`/` and `/uploads`) after `:ensure_authenticated_user`.

---

## Out of Scope

- Per-LiveView/per-action authorization
- Multi-guild support
- Re-checking on WebSocket lifecycle (LiveView mount)
- Dedicated denial page
