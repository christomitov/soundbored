# Spec: Discord Role-Gated Access

**Status:** Draft
**Date:** 2026-04-27
**Author:** —

---

## Summary

Restrict web access to the soundboard to Discord users who are members of a configured guild **and** hold at least one configured role. Verification happens at OAuth login time and is re-checked periodically per session. If the feature is not configured (env vars unset), behavior is unchanged — anyone who completes Discord OAuth gets in.

---

## Motivation

Today, any Discord user who completes the OAuth flow can access the soundboard. The bot is typically deployed for a single Discord community, so the operator wants to gate access to members of that community holding specific roles (e.g., a `soundboard-users` role). This must be enforced server-side, fail closed, and not require a manual user-management workflow.

---

## User-Facing Behavior

| Scenario | Result |
|---|---|
| Feature not configured (no guild/role env vars set) | Open access — current behavior preserved |
| User authenticates, has a required role | Logged in normally |
| User authenticates, not in guild OR lacks all required roles | No user record created (if first login). Session cleared. Redirected to `/` with `"Error signing in"` flash |
| Logged-in user loses required role | At next re-check (default 15 min after last verification), session is cleared and they are redirected to `/` with the same flash |
| Discord API call fails (network, rate limit, etc.) | Fails closed — user is denied access |

The flash message is intentionally generic (matches the existing auth-failure message) to avoid leaking information about why access was denied.

---

## Configuration

Three new env vars, parsed in `config/runtime.exs` for both `:dev` and `:prod` blocks:

| Env Var | Type | Default | Description |
|---|---|---|---|
| `DISCORD_REQUIRED_GUILD_ID` | string | `nil` | Guild snowflake ID. Bot must be a member of this guild. |
| `DISCORD_REQUIRED_ROLE_IDS` | comma-separated strings | `""` | Role snowflake IDs. User must hold at least one. |
| `DISCORD_ROLE_RECHECK_INTERVAL_SECONDS` | integer | `900` | Seconds between role re-checks during an active session. |

The feature is **enabled** only when `DISCORD_REQUIRED_GUILD_ID` is set AND `DISCORD_REQUIRED_ROLE_IDS` is non-empty after parsing. Either condition unmet → feature disabled, no role checks performed.

`.env.example` is updated with these three vars (commented out by default to preserve open-access behavior on fresh installs).

---

## Architecture

### New module: `Soundboard.Discord.RoleChecker`

Location: `lib/soundboard/discord/role_checker.ex`

Wraps `EDA.API.Member.get/2` (the existing convention for Discord REST calls — see `Soundboard.Discord.BotIdentity` for the same pattern).

Public API:

```elixir
@spec feature_enabled?() :: boolean()
@spec authorized?(discord_id :: String.t()) :: boolean()
```

`authorized?/1` returns `true` when the feature is unconfigured (open access), `true` when the member holds any required role, and `false` otherwise — including network errors, "user not in guild" responses, and any non-`{:ok, _}` return from `EDA.API.Member.get/2`.

### Updated controller: `SoundboardWeb.AuthController`

The `callback/2` clause is restructured with a `with` chain so the role check runs **before** `find_or_create_user`:

```elixir
with true <- RoleChecker.authorized?(auth.uid),
     {:ok, user} <- find_or_create_user(user_params) do
  conn
  |> put_session(:user_id, user.id)
  |> put_session(:roles_verified_at, System.system_time(:second))
  |> redirect(to: "/")
else
  false ->
    conn
    |> clear_session()
    |> put_flash(:error, "Error signing in")
    |> redirect(to: "/")

  {:error, _reason} ->
    conn
    |> put_flash(:error, "Error signing in")
    |> redirect(to: "/")
end
```

Rationale for role-check-before-DB-write: avoid creating user records for users who will never be authorized to use the application.

### New plug: `SoundboardWeb.Plugs.RoleCheck`

Location: `lib/soundboard_web/plugs/role_check.ex`

Behavior:
1. If no `current_user` assigned → pass through (defers to `ensure_authenticated_user`).
2. If feature disabled → pass through.
3. If `roles_verified_at` is present and within `interval_seconds` → pass through.
4. Otherwise re-check via `RoleChecker.authorized?/1`:
   - Authorized → update `roles_verified_at` to now, pass through.
   - Not authorized → `clear_session/1`, flash `"Error signing in"`, redirect to `/`, halt.

A missing or non-integer `roles_verified_at` is treated as stale (forces a re-check). This handles legacy sessions cleanly when the feature is enabled for the first time.

### Router wiring

A new pipeline is added matching the existing `:require_browser_basic_auth` style:

```elixir
pipeline :require_role_check do
  plug SoundboardWeb.Plugs.RoleCheck
end
```

Both protected scopes are updated:

```elixir
pipe_through [:browser, :auth, :ensure_authenticated_user, :require_role_check, :require_browser_basic_auth]
```

Applies to both the `/` scope (LiveViews) and `/uploads` scope.

---

## Data Flow

**Login (happy path):**
1. User completes Discord OAuth → Ueberauth populates `conn.assigns.ueberauth_auth`.
2. `AuthController.callback/2` extracts `auth.uid` (Discord user ID).
3. `RoleChecker.authorized?(uid)` → `EDA.API.Member.get(guild_id, uid)` → check returned `roles` against required list.
4. On success: find-or-create the local `User`, set `:user_id` and `:roles_verified_at` in session.

**Subsequent requests (within interval):**
1. `:browser` → `:auth` → `ensure_authenticated_user` (user assigned) → `RoleCheck` (timestamp fresh, pass through) → `:require_browser_basic_auth` → handler.

**Subsequent requests (interval elapsed):**
1. Same as above, but `RoleCheck` calls Discord API.
2. Still authorized → update timestamp, continue.
3. Lost role → clear session, redirect, halt.

**Unconfigured:**
1. `RoleChecker.feature_enabled?()` returns false everywhere → all paths short-circuit. No API calls. No session timestamp meaning.

---

## Failure Modes & Behavior

| Failure | Behavior |
|---|---|
| Discord API timeout/error during login | Login fails (`false` returned, generic flash) |
| Discord API timeout/error during re-check | Session cleared, user redirected with generic flash |
| User not in guild | Treated as unauthorized (`{:error, _}` from `EDA.API.Member.get`) |
| Bot lacks permission to read members | Treated as unauthorized — operator misconfiguration; loud at deployment time |
| `DISCORD_REQUIRED_GUILD_ID` set but `DISCORD_REQUIRED_ROLE_IDS` empty | Feature disabled (both required to gate). Same effect as fully unset. |
| Bot token invalid | All API calls fail → all logins fail. Operator notices immediately. |

The "fail closed" stance is intentional: any uncertainty about role membership denies access rather than granting it.

---

## Testing

Three new/updated test files. Conventions match existing tests in the project (`Mock` library, `Plug.Test`, `SoundboardWeb.ConnCase`).

### `test/soundboard/discord/role_checker_test.exs` (new)

Mirrors `bot_identity_test.exs`. `async: false`, uses `with_mocks` to stub `EDA.API.Member.get/2`. App env is set in `setup` and cleared in `on_exit`.

Cases:
- `feature_enabled?/0` returns `false` when guild ID is missing.
- `feature_enabled?/0` returns `false` when role IDs list is empty.
- `feature_enabled?/0` returns `true` when both are set.
- `authorized?/1` returns `true` when feature is disabled, with no API call made (mocked to `flunk`).
- `authorized?/1` returns `true` when the member has any of the required roles.
- `authorized?/1` returns `false` when the member has none of the required roles.
- `authorized?/1` returns `false` when `EDA.API.Member.get` returns `{:error, _}`.

### `test/soundboard_web/plugs/role_check_test.exs` (new)

Mirrors `basic_auth_test.exs` style — `Plug.Test`, `Plug.Conn`, env manipulation in setup.

Cases:
- Pass through when no `:current_user` is assigned.
- Pass through when feature disabled, regardless of session state.
- Pass through with fresh `:roles_verified_at` (mock `flunk`s on API call).
- Triggers re-check when `:roles_verified_at` is missing → updates timestamp on success.
- Triggers re-check when `:roles_verified_at` is stale → updates timestamp on success.
- Halts, redirects to `/`, clears `:user_id` when re-check returns unauthorized.

### `test/soundboard_web/controllers/auth_controller_test.exs` (updated)

Existing tests run with the feature disabled (no env set), so they continue to pass with one addition: the success cases assert that `:roles_verified_at` is set in the session.

New cases (with feature enabled via app env + `RoleChecker.authorized?/1` mocked):
- Authorized callback → user record created, `:user_id` and `:roles_verified_at` both set in session.
- Unauthorized callback → no user record created (`Repo.get_by(User, discord_id: ...)` returns `nil`), session cleared, redirect to `/`, `"Error signing in"` flash.

### Coverage target

Per AGENTS.md: aim >90% for new code. `RoleChecker` and `RoleCheck` are small, branch-light modules — easy to hit.

---

## Out of Scope

- **Per-LiveView role gating** — this spec gates the entire app at the pipeline level. Per-action authorization (e.g., "admin role can delete sounds") is a separate concern.
- **Caching `EDA.API.Member.get` results across users** — the session timestamp already provides per-user caching; cross-user caching would require ETS/GenServer and is unjustified for typical small-community deployment sizes.
- **Notifying users about why access was denied** — using a generic flash is a deliberate choice (Option C from brainstorming). A dedicated denial page is a future option if needed.
- **Re-checking on WebSocket connection (LiveView mount)** — the plug runs on the initial HTTP request that establishes the LiveView; a long-lived WebSocket can outlive the recheck interval. This is acceptable for the initial implementation given that re-checks still happen on subsequent navigations and the session is signed/encrypted.

---

## Implementation Order

1. Add config plumbing (`runtime.exs`, `.env.example`).
2. Add `Soundboard.Discord.RoleChecker` + tests.
3. Add `SoundboardWeb.Plugs.RoleCheck` + tests.
4. Wire pipeline in `router.ex`.
5. Update `AuthController.callback/2` + tests.
6. Run `mix format`, `mix credo --strict`, `mix test` (per AGENTS.md gates).
