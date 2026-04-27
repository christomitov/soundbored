# Discord Role-Gated Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict web access to Discord users who hold a configured role in a configured guild, with verification at login and periodic re-checks.

**Architecture:** A new pure-ish module `Soundboard.Discord.RoleChecker` wraps `EDA.API.Member.get/2` to check guild role membership. The OAuth callback denies the login (and skips DB user creation) when the check fails. A new `SoundboardWeb.Plugs.RoleCheck` plug runs in the protected pipeline and re-verifies via the Discord API when a session-stored timestamp is older than the configured interval.

**Tech Stack:** Elixir 1.19, Phoenix 1.8, Ecto/SQLite, Ueberauth (Discord), EDA (Elixir Discord Adapter), Mock library for tests.

**Branch:** `discord-role-gated-access` (already created from `main`)

**Spec:** `docs/specs/discord-role-gated-access.md`

---

## File Map

**Create:**
- `lib/soundboard/discord/role_checker.ex` — role authorization logic
- `lib/soundboard_web/plugs/role_check.ex` — periodic re-check plug
- `test/soundboard/discord/role_checker_test.exs`
- `test/soundboard_web/plugs/role_check_test.exs`

**Modify:**
- `config/runtime.exs` — env var parsing in both `:dev` and `:prod` blocks
- `.env.example` — document new env vars
- `lib/soundboard_web/controllers/auth_controller.ex` — login-time role check
- `lib/soundboard_web/router.ex` — new pipeline + wire into protected scopes
- `test/soundboard_web/controllers/auth_controller_test.exs` — new test cases

---

## Key Conventions (from AGENTS.md and existing code)

- Run `mix format` before every commit.
- Module pattern for Discord wrappers: see `lib/soundboard/discord/bot_identity.ex` — short `@moduledoc false`, simple functions, no GenServer.
- Test pattern for Discord wrappers: see `test/soundboard/discord/bot_identity_test.exs` — `use ExUnit.Case, async: false`, `import Mock`, `with_mock` / `with_mocks` blocks.
- Plug pattern: see `lib/soundboard_web/plugs/basic_auth.ex` and its test.
- Phoenix conn-with-session test pattern: see `test/soundboard_web/controllers/auth_controller_test.exs` lines 11–15 (`init_test_session(%{}) |> fetch_session() |> fetch_flash()`).
- Commit messages: imperative mood, concise (e.g., "Add role checker module", "Wire role check plug into protected pipeline").
- Each commit should include a `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` trailer.

---

## Task 1: Add config plumbing for required guild/role env vars

**Goal:** New env vars are read by `runtime.exs` in both `:dev` and `:prod` blocks and stored under `:soundboard` app config keys, with sensible defaults that leave the feature **disabled** when unset.

**Files:**
- Modify: `config/runtime.exs` (add lines in `:dev` block around line 32–90 and in `:prod` block around line 93–221)
- Modify: `.env.example`

**Acceptance Criteria:**
- [ ] `Application.get_env(:soundboard, :required_guild_id)` returns `nil` when `DISCORD_REQUIRED_GUILD_ID` is unset.
- [ ] `Application.get_env(:soundboard, :required_role_ids)` returns `[]` when `DISCORD_REQUIRED_ROLE_IDS` is unset.
- [ ] `Application.get_env(:soundboard, :role_recheck_interval_seconds)` returns `900` when `DISCORD_ROLE_RECHECK_INTERVAL_SECONDS` is unset.
- [ ] `DISCORD_REQUIRED_ROLE_IDS=role1,role2,role3` parses to `["role1", "role2", "role3"]`.
- [ ] `mix compile` succeeds with no warnings.
- [ ] `.env.example` documents all three new variables (commented out so they don't accidentally enable the feature on copy).

**Verify:** `mix compile --warnings-as-errors`

**Steps:**

- [ ] **Step 1: Add env var parsing to the `:dev` block in `config/runtime.exs`**

The `:dev` block already starts with `if config_env() == :dev do` near line 32. Inside this block, just before the existing `config :soundboard, ...` call (around line 81), add:

```elixir
  required_guild_id = env!("DISCORD_REQUIRED_GUILD_ID", :string, nil)

  required_role_ids =
    "DISCORD_REQUIRED_ROLE_IDS"
    |> env!(:string, "")
    |> String.split(",", trim: true)

  role_recheck_interval_seconds = env!("DISCORD_ROLE_RECHECK_INTERVAL_SECONDS", :integer, 900)
```

Then extend the existing `config :soundboard, ...` call (around line 81) to include the three new keys. The block should end up looking like:

```elixir
  config :soundboard,
    discord_token: discord_token,
    voice_rtp_probe: voice_rtp_probe,
    voice_rtp_probe_timeout_ms: voice_rtp_probe_timeout_ms,
    ffmpeg_available: ffmpeg_available,
    required_guild_id: required_guild_id,
    required_role_ids: required_role_ids,
    role_recheck_interval_seconds: role_recheck_interval_seconds
```

- [ ] **Step 2: Add the same parsing to the `:prod` block**

The `:prod` block starts with `if config_env() == :prod and is_nil(env!("SKIP_RUNTIME_CONFIG", :string, nil)) do` near line 93. Find the existing `config :soundboard, ...` block (around line 190) and add the same three `env!` parses just above it, then extend the config call the same way:

```elixir
  required_guild_id = env!("DISCORD_REQUIRED_GUILD_ID", :string, nil)

  required_role_ids =
    "DISCORD_REQUIRED_ROLE_IDS"
    |> env!(:string, "")
    |> String.split(",", trim: true)

  role_recheck_interval_seconds = env!("DISCORD_ROLE_RECHECK_INTERVAL_SECONDS", :integer, 900)

  config :soundboard,
    discord_token: discord_token,
    voice_rtp_probe: voice_rtp_probe,
    voice_rtp_probe_timeout_ms: voice_rtp_probe_timeout_ms,
    ffmpeg_available: ffmpeg_available,
    required_guild_id: required_guild_id,
    required_role_ids: required_role_ids,
    role_recheck_interval_seconds: role_recheck_interval_seconds
```

- [ ] **Step 3: Update `.env.example`**

Append the following block to `.env.example` (it is consumed by Dotenvy in `runtime.exs`):

```
# Discord role-gated access (optional)
# When BOTH DISCORD_REQUIRED_GUILD_ID and DISCORD_REQUIRED_ROLE_IDS are set,
# only Discord users who are members of the guild AND hold at least one of the
# listed roles can sign in. The bot must already be a member of this guild.
# Leave both unset to allow open access (current default behavior).
#DISCORD_REQUIRED_GUILD_ID=
#DISCORD_REQUIRED_ROLE_IDS=
# How often (in seconds) to re-verify a logged-in user's roles via the Discord API.
#DISCORD_ROLE_RECHECK_INTERVAL_SECONDS=900
```

- [ ] **Step 4: Verify**

Run: `mix compile --warnings-as-errors`
Expected: clean compile, no warnings.

- [ ] **Step 5: Format + commit**

```bash
mix format config/runtime.exs
git add config/runtime.exs .env.example
git commit -m "$(cat <<'EOF'
Add config plumbing for Discord role-gated access

Reads DISCORD_REQUIRED_GUILD_ID, DISCORD_REQUIRED_ROLE_IDS, and
DISCORD_ROLE_RECHECK_INTERVAL_SECONDS in both :dev and :prod runtime
blocks. Defaults leave the feature disabled (nil guild, empty role
list) so existing deployments remain unchanged.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Implement Soundboard.Discord.RoleChecker with TDD

**Goal:** A new module exposes `feature_enabled?/0` and `authorized?/1`. When the feature is disabled, `authorized?/1` returns `true` without making any API call. When enabled, it calls `EDA.API.Member.get/2` and checks for any matching role. Any error or non-`:ok` return value fails closed.

**Files:**
- Create: `lib/soundboard/discord/role_checker.ex`
- Create: `test/soundboard/discord/role_checker_test.exs`

**Acceptance Criteria:**
- [ ] `feature_enabled?/0` returns `false` when `:required_guild_id` is `nil`.
- [ ] `feature_enabled?/0` returns `false` when `:required_role_ids` is `[]`.
- [ ] `feature_enabled?/0` returns `true` only when both are set.
- [ ] `authorized?/1` returns `true` when feature is disabled (no API call made — `flunk` on the mock proves this).
- [ ] `authorized?/1` returns `true` when `EDA.API.Member.get/2` returns `{:ok, %{"roles" => [...]}}` containing at least one configured role ID.
- [ ] `authorized?/1` returns `false` when none of the configured roles are in the member's role list.
- [ ] `authorized?/1` returns `false` when `EDA.API.Member.get/2` returns `{:error, _}`.
- [ ] All tests pass.

**Verify:** `mix test test/soundboard/discord/role_checker_test.exs`

**Steps:**

- [ ] **Step 1: Write the failing test file**

Create `test/soundboard/discord/role_checker_test.exs` with the full test code below. This mirrors the `bot_identity_test.exs` pattern (`use ExUnit.Case, async: false`, `import Mock`, `with_mock`).

```elixir
defmodule Soundboard.Discord.RoleCheckerTest do
  use ExUnit.Case, async: false

  import Mock

  alias EDA.API.Member
  alias Soundboard.Discord.RoleChecker

  setup do
    previous_guild = Application.get_env(:soundboard, :required_guild_id)
    previous_roles = Application.get_env(:soundboard, :required_role_ids)

    on_exit(fn ->
      restore_env(:required_guild_id, previous_guild)
      restore_env(:required_role_ids, previous_roles || [])
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:soundboard, key)
  defp restore_env(key, value), do: Application.put_env(:soundboard, key, value)

  describe "feature_enabled?/0" do
    test "returns false when guild_id is missing" do
      Application.put_env(:soundboard, :required_guild_id, nil)
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      refute RoleChecker.feature_enabled?()
    end

    test "returns false when role_ids is empty" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, [])

      refute RoleChecker.feature_enabled?()
    end

    test "returns true when both guild_id and role_ids are configured" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      assert RoleChecker.feature_enabled?()
    end
  end

  describe "authorized?/1" do
    test "returns true when feature is disabled and does not call the API" do
      Application.put_env(:soundboard, :required_guild_id, nil)
      Application.put_env(:soundboard, :required_role_ids, [])

      with_mock Member, get: fn _, _ -> flunk("API should not be called when disabled") end do
        assert RoleChecker.authorized?("user1")
      end
    end

    test "returns true when member has at least one required role" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1", "r2"])

      with_mock Member,
        get: fn "g1", "user1" -> {:ok, %{"roles" => ["other", "r2"]}} end do
        assert RoleChecker.authorized?("user1")
        assert_called(Member.get("g1", "user1"))
      end
    end

    test "returns false when member has none of the required roles" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      with_mock Member,
        get: fn "g1", "user1" -> {:ok, %{"roles" => ["other_role"]}} end do
        refute RoleChecker.authorized?("user1")
      end
    end

    test "returns false when API returns an error" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      with_mock Member, get: fn _, _ -> {:error, :not_found} end do
        refute RoleChecker.authorized?("user1")
      end
    end

    test "returns false when API response shape is unexpected" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      with_mock Member, get: fn _, _ -> {:ok, %{"unexpected" => "shape"}} end do
        refute RoleChecker.authorized?("user1")
      end
    end
  end
end
```

- [ ] **Step 2: Run test, confirm it fails**

Run: `mix test test/soundboard/discord/role_checker_test.exs`
Expected: compilation error / `Soundboard.Discord.RoleChecker` is not loaded.

- [ ] **Step 3: Implement the module**

Create `lib/soundboard/discord/role_checker.ex`:

```elixir
defmodule Soundboard.Discord.RoleChecker do
  @moduledoc false

  @doc """
  Returns true when role-gating is configured (both guild ID and at least
  one role ID present). When false, `authorized?/1` is a no-op that returns
  true.
  """
  def feature_enabled? do
    guild_id = Application.get_env(:soundboard, :required_guild_id)
    role_ids = Application.get_env(:soundboard, :required_role_ids, [])

    not is_nil(guild_id) and role_ids != []
  end

  @doc """
  Returns true when the user is authorized to access the soundboard. When
  the feature is disabled, always returns true. When enabled, calls the
  Discord API to fetch the user's guild member record and checks for any
  matching required role. Any error response (including the user not being
  in the guild) returns false.
  """
  def authorized?(discord_id) when is_binary(discord_id) do
    if feature_enabled?() do
      check_roles(discord_id)
    else
      true
    end
  end

  defp check_roles(discord_id) do
    guild_id = Application.get_env(:soundboard, :required_guild_id)
    required_role_ids = Application.get_env(:soundboard, :required_role_ids, [])

    case EDA.API.Member.get(guild_id, discord_id) do
      {:ok, %{"roles" => member_roles}} when is_list(member_roles) ->
        Enum.any?(required_role_ids, &(&1 in member_roles))

      _ ->
        false
    end
  end
end
```

- [ ] **Step 4: Run test, confirm it passes**

Run: `mix test test/soundboard/discord/role_checker_test.exs`
Expected: 8 tests, 0 failures.

- [ ] **Step 5: Format + commit**

```bash
mix format lib/soundboard/discord/role_checker.ex test/soundboard/discord/role_checker_test.exs
git add lib/soundboard/discord/role_checker.ex test/soundboard/discord/role_checker_test.exs
git commit -m "$(cat <<'EOF'
Add Soundboard.Discord.RoleChecker

Wraps EDA.API.Member.get/2 to determine whether a Discord user is
authorized to use the soundboard, based on guild membership and a
configured set of role IDs. Fails closed on any API error or
unexpected response shape. When the feature is unconfigured, the
check is a no-op that returns true.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add login-time role check to AuthController

**Goal:** The OAuth callback verifies the user's role membership **before** creating or fetching the local user record. On success, both `:user_id` and `:roles_verified_at` are stored in the session. On failure, the session is cleared, no user record is created, and the user is redirected to `/` with the same generic flash used by other auth failures.

**Files:**
- Modify: `lib/soundboard_web/controllers/auth_controller.ex`
- Modify: `test/soundboard_web/controllers/auth_controller_test.exs`

**Acceptance Criteria:**
- [ ] When `RoleChecker.authorized?/1` returns `true`, the user record is created/found, `:user_id` is set in the session, and `:roles_verified_at` is set in the session as an integer.
- [ ] When `RoleChecker.authorized?/1` returns `false`, no user record is created (`Repo.get_by(User, discord_id: ...)` returns `nil`), no session is set, the user is redirected to `/`, and the flash error is `"Error signing in"`.
- [ ] All existing `auth_controller_test.exs` tests still pass (with feature disabled — the test env has no `DISCORD_REQUIRED_*` vars set).
- [ ] Existing success tests are extended to assert `:roles_verified_at` is set.

**Verify:** `mix test test/soundboard_web/controllers/auth_controller_test.exs`

**Steps:**

- [ ] **Step 1: Update existing success tests to assert `:roles_verified_at`**

In `test/soundboard_web/controllers/auth_controller_test.exs`, modify the two tests that exercise a successful callback:

In `test "callback/2 creates new user on successful auth"` (line ~49), after the existing `assert get_session(conn, :user_id)` line, add:

```elixir
      assert is_integer(get_session(conn, :roles_verified_at))
```

In `test "callback/2 uses existing user if found"` (line ~72), after the existing `assert get_session(conn, :user_id) == existing_user.id` line, add:

```elixir
      assert is_integer(get_session(conn, :roles_verified_at))
```

- [ ] **Step 2: Add new test for unauthorized callback path**

Add this test inside the `describe "auth flow"` block in `test/soundboard_web/controllers/auth_controller_test.exs`. It uses `Mock` to make `RoleChecker.authorized?/1` return `false`, then asserts the controller never created a user and never set `:user_id`:

```elixir
    test "callback/2 denies and skips user creation when role check fails", %{conn: conn} do
      auth_data = %{
        uid: "12345",
        info: %{
          nickname: "TestUser",
          image: "test_avatar.jpg"
        }
      }

      with_mock Soundboard.Discord.RoleChecker, [:passthrough],
        authorized?: fn "12345" -> false end do
        conn =
          conn
          |> assign(:ueberauth_auth, auth_data)
          |> get(~p"/auth/discord/callback")

        assert redirected_to(conn) == "/"
        refute get_session(conn, :user_id)
        refute get_session(conn, :roles_verified_at)
        refute Repo.get_by(User, discord_id: "12345")
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Error signing in"
      end
    end
```

You will also need to add `import Mock` to the top of the test file (under the existing `import ExUnit.CaptureLog` line).

- [ ] **Step 3: Run tests, confirm the new test fails and existing tests fail on the new assertion**

Run: `mix test test/soundboard_web/controllers/auth_controller_test.exs`
Expected: 3 failures (2 existing tests now expecting `:roles_verified_at`, 1 new test expecting `RoleChecker` to be invoked).

- [ ] **Step 4: Update the controller**

Modify `lib/soundboard_web/controllers/auth_controller.ex`. Add the alias near the top (after the existing `alias` lines):

```elixir
  alias Soundboard.Discord.RoleChecker
```

Replace the entire `def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params)` clause (lines 21–39) with:

```elixir
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_params = %{
      discord_id: auth.uid,
      username: auth.info.nickname || auth.info.name,
      avatar: auth.info.image
    }

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
  end
```

- [ ] **Step 5: Run tests, confirm all pass**

Run: `mix test test/soundboard_web/controllers/auth_controller_test.exs`
Expected: all tests pass (existing + new).

- [ ] **Step 6: Format + commit**

```bash
mix format lib/soundboard_web/controllers/auth_controller.ex test/soundboard_web/controllers/auth_controller_test.exs
git add lib/soundboard_web/controllers/auth_controller.ex test/soundboard_web/controllers/auth_controller_test.exs
git commit -m "$(cat <<'EOF'
Verify Discord role membership at login

The OAuth callback now calls Soundboard.Discord.RoleChecker.authorized?/1
with the Discord user ID before creating or looking up the local user
record. When unauthorized, no user record is created, the session is
cleared, and the user is redirected to / with a generic flash. On
success, :roles_verified_at is stored alongside :user_id for the
periodic re-check plug to consume.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Implement SoundboardWeb.Plugs.RoleCheck with TDD

**Goal:** A new plug runs after `ensure_authenticated_user` in the protected pipeline. It reads `:roles_verified_at` from the session and re-verifies via `RoleChecker.authorized?/1` if the timestamp is missing, non-integer, or older than the configured interval. On successful re-check, the timestamp is refreshed. On failure, the session is cleared, the user is redirected to `/`, and the conn is halted.

**Files:**
- Create: `lib/soundboard_web/plugs/role_check.ex`
- Create: `test/soundboard_web/plugs/role_check_test.exs`

**Acceptance Criteria:**
- [ ] No `:current_user` assigned → conn passes through, not halted, no API call.
- [ ] `RoleChecker.feature_enabled?/0` returns false → conn passes through, not halted, no API call.
- [ ] Feature enabled, `:roles_verified_at` present and within interval → conn passes through, not halted, no API call.
- [ ] Feature enabled, `:roles_verified_at` missing → re-check happens; if authorized, timestamp is set, conn passes through.
- [ ] Feature enabled, `:roles_verified_at` older than interval → re-check happens; if authorized, timestamp is updated, conn passes through.
- [ ] Feature enabled, re-check returns false → conn is halted with status 302, redirected to `/`, `:user_id` is no longer in the session.

**Verify:** `mix test test/soundboard_web/plugs/role_check_test.exs`

**Steps:**

- [ ] **Step 1: Write the failing test file**

Create `test/soundboard_web/plugs/role_check_test.exs`:

```elixir
defmodule SoundboardWeb.Plugs.RoleCheckTest do
  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.Discord.RoleChecker
  alias SoundboardWeb.Plugs.RoleCheck

  setup %{conn: conn} do
    previous_guild = Application.get_env(:soundboard, :required_guild_id)
    previous_roles = Application.get_env(:soundboard, :required_role_ids)
    previous_interval = Application.get_env(:soundboard, :role_recheck_interval_seconds)

    on_exit(fn ->
      restore_env(:required_guild_id, previous_guild)
      restore_env(:required_role_ids, previous_roles || [])
      restore_env(:role_recheck_interval_seconds, previous_interval)
    end)

    conn =
      conn
      |> init_test_session(%{})
      |> fetch_session()
      |> fetch_flash()

    %{conn: conn}
  end

  defp restore_env(key, nil), do: Application.delete_env(:soundboard, key)
  defp restore_env(key, value), do: Application.put_env(:soundboard, key, value)

  defp enable_feature do
    Application.put_env(:soundboard, :required_guild_id, "g1")
    Application.put_env(:soundboard, :required_role_ids, ["r1"])
    Application.put_env(:soundboard, :role_recheck_interval_seconds, 900)
  end

  defp disable_feature do
    Application.put_env(:soundboard, :required_guild_id, nil)
    Application.put_env(:soundboard, :required_role_ids, [])
  end

  test "passes through when no current_user is assigned", %{conn: conn} do
    enable_feature()

    with_mock RoleChecker, [:passthrough],
      authorized?: fn _ -> flunk("authorized? should not be called") end do
      conn = RoleCheck.call(conn, %{})
      refute conn.halted
    end
  end

  test "passes through when feature is disabled", %{conn: conn} do
    disable_feature()

    user = %User{id: 1, discord_id: "u1"}

    with_mock RoleChecker, [:passthrough],
      authorized?: fn _ -> flunk("authorized? should not be called") end do
      conn =
        conn
        |> assign(:current_user, user)
        |> RoleCheck.call(%{})

      refute conn.halted
    end
  end

  test "passes through with fresh timestamp without re-checking", %{conn: conn} do
    enable_feature()

    user = %User{id: 1, discord_id: "u1"}
    fresh_ts = System.system_time(:second)

    with_mock RoleChecker, [:passthrough],
      authorized?: fn _ -> flunk("authorized? should not be called") end do
      conn =
        conn
        |> assign(:current_user, user)
        |> put_session(:roles_verified_at, fresh_ts)
        |> RoleCheck.call(%{})

      refute conn.halted
    end
  end

  test "rechecks and updates the timestamp when stale and still authorized", %{conn: conn} do
    enable_feature()
    Application.put_env(:soundboard, :role_recheck_interval_seconds, 1)

    user = %User{id: 1, discord_id: "u1"}
    stale_ts = System.system_time(:second) - 60

    with_mock RoleChecker, [:passthrough], authorized?: fn "u1" -> true end do
      conn =
        conn
        |> assign(:current_user, user)
        |> put_session(:roles_verified_at, stale_ts)
        |> RoleCheck.call(%{})

      refute conn.halted
      assert get_session(conn, :roles_verified_at) > stale_ts
      assert_called(RoleChecker.authorized?("u1"))
    end
  end

  test "treats missing timestamp as stale and rechecks", %{conn: conn} do
    enable_feature()

    user = %User{id: 1, discord_id: "u1"}

    with_mock RoleChecker, [:passthrough], authorized?: fn "u1" -> true end do
      conn =
        conn
        |> assign(:current_user, user)
        |> RoleCheck.call(%{})

      refute conn.halted
      assert is_integer(get_session(conn, :roles_verified_at))
      assert_called(RoleChecker.authorized?("u1"))
    end
  end

  test "halts and clears session when recheck returns unauthorized", %{conn: conn} do
    enable_feature()

    user = %User{id: 1, discord_id: "u1"}

    with_mock RoleChecker, [:passthrough], authorized?: fn "u1" -> false end do
      conn =
        conn
        |> assign(:current_user, user)
        |> put_session(:user_id, 1)
        |> RoleCheck.call(%{})

      assert conn.halted
      assert conn.status == 302
      refute get_session(conn, :user_id)
      refute get_session(conn, :roles_verified_at)
    end
  end
end
```

- [ ] **Step 2: Run tests, confirm they fail**

Run: `mix test test/soundboard_web/plugs/role_check_test.exs`
Expected: compilation error — `SoundboardWeb.Plugs.RoleCheck` is not loaded.

- [ ] **Step 3: Implement the plug**

Create `lib/soundboard_web/plugs/role_check.ex`:

```elixir
defmodule SoundboardWeb.Plugs.RoleCheck do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias Soundboard.Discord.RoleChecker

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn

      not RoleChecker.feature_enabled?() ->
        conn

      stale?(conn) ->
        recheck(conn, user)

      true ->
        conn
    end
  end

  defp stale?(conn) do
    case get_session(conn, :roles_verified_at) do
      ts when is_integer(ts) ->
        System.system_time(:second) - ts >= interval_seconds()

      _ ->
        true
    end
  end

  defp recheck(conn, user) do
    if RoleChecker.authorized?(user.discord_id) do
      put_session(conn, :roles_verified_at, System.system_time(:second))
    else
      conn
      |> clear_session()
      |> put_flash(:error, "Error signing in")
      |> redirect(to: "/")
      |> halt()
    end
  end

  defp interval_seconds do
    Application.get_env(:soundboard, :role_recheck_interval_seconds, 900)
  end
end
```

- [ ] **Step 4: Run tests, confirm all pass**

Run: `mix test test/soundboard_web/plugs/role_check_test.exs`
Expected: 6 tests, 0 failures.

- [ ] **Step 5: Format + commit**

```bash
mix format lib/soundboard_web/plugs/role_check.ex test/soundboard_web/plugs/role_check_test.exs
git add lib/soundboard_web/plugs/role_check.ex test/soundboard_web/plugs/role_check_test.exs
git commit -m "$(cat <<'EOF'
Add SoundboardWeb.Plugs.RoleCheck

Re-verifies a logged-in user's Discord role membership when the
session-stored :roles_verified_at timestamp is missing or older than
the configured interval. On successful re-check the timestamp is
refreshed; on failure the session is cleared and the user is
redirected to / with a generic flash. No-op when no current_user is
assigned or when the feature is disabled.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire RoleCheck plug into the protected pipeline

**Goal:** Both protected scopes (`/` and `/uploads`) invoke the new plug after `ensure_authenticated_user`. With the feature disabled (test env default), the full test suite continues to pass.

**Files:**
- Modify: `lib/soundboard_web/router.ex`

**Acceptance Criteria:**
- [ ] A new `:require_role_check` pipeline is defined that plugs `SoundboardWeb.Plugs.RoleCheck`.
- [ ] The `scope "/", SoundboardWeb` block uses `:require_role_check` after `:ensure_authenticated_user`.
- [ ] The `scope "/uploads"` block uses `:require_role_check` after `:ensure_authenticated_user`.
- [ ] `mix test` passes the entire suite.
- [ ] `mix credo --strict` passes.
- [ ] `mix format --check-formatted` passes.

**Verify:** `mix test && mix credo --strict && mix format --check-formatted`

**Steps:**

- [ ] **Step 1: Add the new pipeline to `router.ex`**

In `lib/soundboard_web/router.ex`, add this pipeline immediately after the existing `pipeline :require_browser_basic_auth do ... end` block (around line 13–15):

```elixir
  pipeline :require_role_check do
    plug SoundboardWeb.Plugs.RoleCheck
  end
```

- [ ] **Step 2: Update both protected scopes to include the new pipeline**

Replace the `pipe_through` line in the `scope "/", SoundboardWeb` block (line 46):

```elixir
    pipe_through [:browser, :auth, :ensure_authenticated_user, :require_role_check, :require_browser_basic_auth]
```

Replace the `pipe_through` line in the `scope "/uploads"` block (line 55):

```elixir
    pipe_through [:browser, :auth, :ensure_authenticated_user, :require_role_check, :require_browser_basic_auth]
```

- [ ] **Step 3: Run the full test suite**

Run: `mix test`
Expected: all tests pass. (The feature is disabled by default in `config/test.exs` because no env vars are set, so the new plug is a no-op for every existing test.)

- [ ] **Step 4: Run lint checks**

Run: `mix format --check-formatted`
Expected: clean (no files need formatting).

Run: `mix credo --strict`
Expected: clean (no issues, or only existing pre-existing issues unrelated to this change).

If credo flags anything in the new code, fix it inline before committing.

- [ ] **Step 5: Commit**

```bash
git add lib/soundboard_web/router.ex
git commit -m "$(cat <<'EOF'
Wire RoleCheck plug into protected pipeline

Adds a :require_role_check pipeline running SoundboardWeb.Plugs.RoleCheck
and inserts it into both protected scopes (/ and /uploads) after
:ensure_authenticated_user. With no DISCORD_REQUIRED_* env vars set the
plug is a no-op, preserving current behavior for existing deployments.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Final precommit verification**

Run the project's full precommit alias to confirm nothing else is broken:

Run: `mix precommit`
Expected: clean run — `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `credo --strict`, `test`, `ex_dna` all pass.

If `mix precommit` flags anything, fix it and amend or add a follow-up commit before considering the plan complete.

---

## Summary of Behavior After Implementation

- **Open access (no env vars set):** Discord OAuth login works exactly as before. `:roles_verified_at` is set in the session but ignored by the plug because the feature is disabled.
- **Restricted access (env vars set, bot in guild):** Login fails for users without a required role — no DB record created, generic error flash. Logged-in users are silently re-verified up to once per `DISCORD_ROLE_RECHECK_INTERVAL_SECONDS`. Users who lose the required role are kicked at the next re-check.
- **Discord API outage:** Login fails for all new users; existing logged-in users with fresh timestamps continue to function until the next re-check, at which point they fail closed and are signed out.

## Out of Scope (Confirmed)

- Multi-guild support (would require AudioPlayer changes — see brainstorming notes).
- Per-LiveView/per-action authorization.
- Re-checking on WebSocket lifecycle (LiveView mount/handle_params).
- Dedicated denial page.
