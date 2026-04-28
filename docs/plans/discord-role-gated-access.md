# Discord Role-Gated Access Implementation Plan

**Status:** Complete
**Spec:** `docs/specs/discord-role-gated-access.md`

**Goal:** Restrict web access to Discord users who hold a configured role in a configured guild, with verification at login and periodic re-checks.

---

## Tasks

### Task 1: Config plumbing ✓
Added `DISCORD_REQUIRED_GUILD_ID`, `DISCORD_REQUIRED_ROLE_IDS`, and `DISCORD_ROLE_RECHECK_INTERVAL_SECONDS` to `config/runtime.exs` (both `:dev` and `:prod` blocks). Updated `.env.example`.

### Task 2: Soundboard.Discord.RoleChecker ✓
New module at `lib/soundboard/discord/role_checker.ex`. Exposes `feature_enabled?/0` and `authorized?/1`. Wraps `EDA.API.Member.get/2`, fails closed on any error.
Tests: `test/soundboard/discord/role_checker_test.exs` (8 tests).

### Task 3: Login-time role check in AuthController ✓
`AuthController.callback/2` calls `RoleChecker.authorized?/1` before `find_or_create_user`. Stores `:roles_verified_at` in session on success. No DB write on failure.
Tests: `test/soundboard_web/controllers/auth_controller_test.exs` (updated).

### Task 4: SoundboardWeb.Plugs.RoleCheck ✓
New plug at `lib/soundboard_web/plugs/role_check.ex`. Re-verifies role membership when session timestamp is missing or stale. Clears session and halts on unauthorized.
Tests: `test/soundboard_web/plugs/role_check_test.exs` (6 tests).

### Task 5: Wire plug into router ✓
Added `:require_role_check` pipeline to `lib/soundboard_web/router.ex`, inserted into both protected scopes after `:ensure_authenticated_user`.
