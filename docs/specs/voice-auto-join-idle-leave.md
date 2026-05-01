# Spec: Voice Channel Auto-Join on Playback & Idle Auto-Leave

**Status:** Implemented  
**Date:** 2026-04-29  
**Author:** Justin Hart

---

## Summary

Three related quality-of-life improvements to bot voice channel management, unified under a single `AUTO_JOIN` mode enum:

1. **Auto-join on play** (`play` mode): when a user triggers sound playback from the web UI or API and the bot is not in any voice channel, the bot automatically joins the user's current Discord voice channel before playing.
2. **Idle auto-leave**: after a configurable period of inactivity (default: 600 seconds), the bot leaves the voice channel. Behavior varies by mode.
3. **`AUTO_JOIN` mode enum**: replaces the old boolean flag with a three-value enum (`play`, `presence`, `false`) that unifies join and leave behavior into one setting.

---

## Motivation

Previously, users had to manually type `!join` in Discord before playing sounds from the web UI. This broke the flow: open the soundboard tab, click a sound, nothing happens, switch to Discord, type `!join`, switch back, click again. The bot also had no way to clean up a lingering voice session after everyone drifted away from a channel.

The original implementation added auto-join on play and a global idle timeout. A follow-up redesign replaced the boolean `AUTO_JOIN` flag with a proper mode enum, aligning join behavior, leave behavior, and idle timeout semantics into a coherent model.

---

## User-Facing Behavior

### `AUTO_JOIN` Modes

| Mode | How bot joins | How bot leaves |
|---|---|---|
| `play` (default) | Joins when a sound is played from the web UI or API | Leaves when last user departs **or** after `VOICE_IDLE_TIMEOUT_SECONDS` of no audio (whichever first). If timeout ≤ 0, only leaves when last user departs. |
| `presence` | Follows users into channels on voice-state updates (existing behavior) | Leaves immediately when last user departs. Idle timeout is **ignored**. |
| `false` | Manual `!join` only | If timeout > 0: leaves after `VOICE_IDLE_TIMEOUT_SECONDS` of being alone (timer starts when last user departs, cancels if a user rejoins). If timeout ≤ 0: never auto-leaves. |

The old `AUTO_JOIN=true` maps to `presence`; `AUTO_JOIN=false` (explicit) maps to `false`; unset now defaults to `play`.

### Auto-Join on Play (in `play` mode)

| Situation | Behavior |
|---|---|
| Bot has no voice channel, user clicks a sound | Bot joins the user's current voice channel and plays the sound |
| User is not in any voice channel | Error: "Bot is not connected to a voice channel. Use !join in Discord first." |
| Actor is `System` (join/leave sounds) | Same error (no Discord identity to look up) |
| Bot already in a channel | Plays normally, unchanged |
| Mode is `presence` or `false` | Error (no auto-join, must use `!join`) |

### Idle Timeout Semantics by Mode

| Event | `play` mode | `presence` mode | `false` mode |
|---|---|---|---|
| Bot joins a channel | Timer starts (if timeout > 0) | No timer | No timer |
| `play_sound` cast | Timer resets | No effect | No effect |
| Last user leaves | Leave immediately | Leave immediately | Start idle timer (if timeout > 0) |
| User rejoins (bot alone) | N/A | N/A | Cancel idle timer |
| Idle timer fires | Leave immediately | Never fires | Leave immediately |
| Bot leaves (any reason) | Timer cancelled | N/A | Timer cancelled |

---

## Architecture & Design

### `AUTO_JOIN` Enum

`AutoJoinPolicy.mode/0` now returns `:presence | :play | false` (the boolean `false`, not an atom, per Elixir convention). Parsing rules:

| `AUTO_JOIN` value | Mode |
|---|---|
| not set | `:play` |
| `play` | `:play` |
| `presence`, `true`, `1`, `yes` | `:presence` |
| `false`, `0`, `no`, any other | `false` |

### Auto-Join Flow (play mode only)

```
Web UI / API → AudioPlayer.play_sound(name, %User{discord_id: ...})
  │
  ▼  (voice_channel is nil AND mode == :play)
AudioPlayer.handle_cast({:play_sound, ...}, %{voice_channel: nil})
  │
  ├─ extract discord_id from actor
  │
  ▼
VoicePresence.find_user_voice_channel(discord_id)
  │  searches all cached guilds via GuildCache
  │
  ├─ {:ok, {guild_id, channel_id}} ──► Voice.join_channel(guild_id, channel_id)
  │                                    update state.voice_channel
  │                                    schedule idle timer (if timeout > 0)
  │                                    proceed with playback
  │
  └─ :not_found ──► Notifier.error("Bot is not connected... Use !join in Discord first.")
```

The join happens directly inside the `handle_cast` body — state is updated synchronously, and playback proceeds in the same message handler. This avoids any circular-cast problem: `VoiceCommands.join_voice_channel` normally calls `AudioPlayer.set_voice_channel` as a success callback, which would deadlock if called from inside `AudioPlayer`. By calling `Voice.join_channel/2` directly and updating state ourselves, we avoid that dependency entirely.

### Last-User-Left Routing

`VoiceRuntime.handle_disconnect` now runs for **all** modes (previously short-circuited for `:disabled`). When the bot is confirmed alone, `bot_alone_action/1` dispatches by mode:

```
bot_alone_action(guild_id)
  :presence  ──► VoiceCommands.leave_voice_channel(guild_id)  (existing path)
  :play      ──► AudioPlayer.last_user_left(guild_id)         (leave immediately)
  false      ──► AudioPlayer.last_user_left(guild_id)         (start idle timer)
```

`AudioPlayer.last_user_left/1` is the new single entry point for non-presence leave events. It:
- `:play` / `:presence`: calls `Voice.leave_channel` directly, clears state.
- `false`: calls `reset_idle_timeout` — starts the idle timer if `VOICE_IDLE_TIMEOUT_SECONDS > 0`, otherwise no-ops (bot stays indefinitely).

### User-Rejoin Cancel (false mode only)

`VoiceRuntime.handle_connect` gains a `false`-mode clause: when a non-bot user joins the bot's current channel, it calls `AudioPlayer.user_joined_channel/1`, which cancels the idle timer. This prevents the bot from leaving when a user briefly steps out and returns.

### Idle Timeout State Machine

```
AudioPlayer state: idle_timeout_ref = {timer_ref, token} | nil

play mode:
  set_voice_channel({guild, chan}) → cancel old timer → schedule new timer
  play_sound cast                 → cancel old timer → schedule new timer (reset)
  set_voice_channel(nil, nil)     → cancel timer
  last_user_left                  → leave immediately, cancel timer
  {:idle_timeout, token}          → leave if token matches, else ignore (stale)

false mode:
  last_user_left                  → schedule timer (if timeout > 0)
  user_joined_channel             → cancel timer
  {:idle_timeout, token}          → leave if token matches, else ignore (stale)

presence mode:
  (no timer ever scheduled)
```

The `{ref, token}` pair guards against a race condition: if `Process.cancel_timer` returns `false` (the message already fired and is in the mailbox), the stale message arrives after a new timer is scheduled. The token mismatch causes it to be silently dropped rather than triggering a spurious leave.

### `IdleTimeoutPolicy` — Disabled State

`timeout_ms/0` now returns `nil` when `VOICE_IDLE_TIMEOUT_SECONDS <= 0` (previously always returned a positive integer). Callers treat `nil` as "disabled" and skip scheduling. This is how `false` mode achieves "never auto-leave" behavior.

### Direct `Voice.leave_channel` vs `VoiceCommands.leave_voice_channel`

`VoiceCommands.leave_voice_channel` would introduce a circular module dependency:
- `VoiceCommands` already calls `AudioPlayer.set_voice_channel` (compile-time dep)
- `AudioPlayer` calling `VoiceCommands` would close the cycle

`AudioPlayer` calls `Voice.leave_channel/1` directly and updates its own state. This is consistent with how `VoiceSession.maintain_connection` already calls `Voice.leave_channel` directly. The `:presence` path continues to use `VoiceCommands` via `VoiceRuntime` (no circular dep there).

### Actor Type Change

Previously, `play_sound` actors from the web layer were plain username strings (e.g. `"justin"`), and from the API layer, a map `%{display_name: username, user_id: db_id}`. Neither carried a `discord_id` usable for voice channel lookup.

Both callers now pass the full `%Soundboard.Accounts.User{}` struct. `PlaybackEngine` already handled this type (via `actor_display_name/1` and `actor_user_id/1` pattern matches), so no downstream changes were needed. The new `actor_discord_id/1` private function in `AudioPlayer` extracts the Discord ID for auto-join, and falls back to `nil` for strings and maps without `discord_id`.

---

## New Function: `VoicePresence.find_user_voice_channel/1`

```elixir
@spec find_user_voice_channel(String.t()) ::
        {:ok, {guild_id :: String.t(), channel_id :: String.t()}} | :not_found
```

Iterates over all guilds in the EDA guild cache and returns the first voice state matching the given Discord user ID. Returns `:not_found` if the user is not in any voice channel or the cache is unavailable.

---

## New Module: `IdleTimeoutPolicy`

```
lib/soundboard/discord/handler/idle_timeout_policy.ex
```

Reads the `VOICE_IDLE_TIMEOUT_SECONDS` environment variable. Returns the timeout in milliseconds, or `nil` if the value is ≤ 0.

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `AUTO_JOIN` | `play` | Join/leave mode. `play` — join on sound playback, leave on idle or last user. `presence` — follow users in, leave when alone. `false` — manual only, leave after idle timeout once alone. |
| `VOICE_IDLE_TIMEOUT_SECONDS` | `600` | Seconds of inactivity before auto-leave. Set to `0` to disable. In `play` mode: resets on each sound played. In `false` mode: starts when last user leaves, cancels if a user rejoins. In `presence` mode: ignored. |

---

## Database Changes

**None.**

---

## File Inventory

| File | Action |
|---|---|
| `lib/soundboard/discord/handler/auto_join_policy.ex` | **Modify** — boolean → enum (`:presence`, `:play`, `false`); remove `enabled?/0` |
| `lib/soundboard/discord/handler/idle_timeout_policy.ex` | **New** — `VOICE_IDLE_TIMEOUT_SECONDS` config reader; returns `nil` when disabled |
| `lib/soundboard/discord/handler/voice_presence.ex` | **Modify** — add `find_user_voice_channel/1` |
| `lib/soundboard/discord/handler/voice_runtime.ex` | **Modify** — mode-aware connect/disconnect routing; `bot_alone_action/1`; `handle_user_rejoin_cancel/1` |
| `lib/soundboard/audio_player.ex` | **Modify** — mode-gated auto-join, idle timer, and last-user-left; new `last_user_left/1` and `user_joined_channel/1` public API |
| `lib/soundboard_web/live/support/sound_playback.ex` | **Modify** — pass `%User{}` struct instead of username string |
| `lib/soundboard_web/controllers/api/sound_controller.ex` | **Modify** — pass `%User{}` struct instead of display-name map |
| `test/soundboard/discord/handler/auto_join_policy_test.exs` | **Rewrite** — enum mode tests; removed `enabled?/0` tests |
| `test/soundboard/discord/handler/idle_timeout_policy_test.exs` | **New** — covers default, custom value, whitespace, disabled (0 and negative) |
| `test/soundboard/discord/handler/voice_presence_test.exs` | **New** — covers `find_user_voice_channel/1` |
| `test/soundboard/discord/handler/voice_runtime_test.exs` | **Modify** — updated mocks to `:presence`; new tests for `play`/`false` mode routing and user-rejoin cancel |
| `test/soundboard_web/audio_player_test.exs` | **Modify** — mode-gated idle timeout and auto-join tests; new `last_user_left` and `user_joined_channel` tests |
| `test/soundboard_web/discord_handler_test.exs` | **Modify** — presence-mode mock; updated leave-sequence assertion |
| `test/soundboard_web/plugs/api_auth_db_token_test.exs` | **Modify** — actor assertion updated |
| `test/soundboard_web/controllers/api/sound_controller_test.exs` | **Modify** — actor assertion updated |
| `test/soundboard_web/live/favorites_live_test.exs` | **Modify** — actor assertion updated |

---

## Testing Strategy

| Layer | What is tested |
|---|---|
| `AutoJoinPolicy` | Test env → `:play`. Default (no env var) → `:play`. `play` → `:play`. `presence`/truthy → `:presence`. `false`/falsy/unknown → `false`. |
| `IdleTimeoutPolicy` | Default → 600,000 ms. Custom value. Whitespace trimming. `0` → `nil`. Negative → `nil`. |
| `VoicePresence.find_user_voice_channel` | User found in a guild. User not found. User in guild but no channel. Multi-guild search. Cache unavailable. |
| `VoiceRuntime` | `handle_disconnect` notifies `AudioPlayer.last_user_left` in `:play` and `false` modes. `handle_connect` cancels idle timer via `AudioPlayer.user_joined_channel` in `false` mode. Bootstrap skips guild scan in `:play` mode. |
| `AudioPlayer` — idle timeout | Timer scheduled on `set_voice_channel` in `:play` mode only. Not scheduled in `:presence` or `false` mode. Timer cancelled on clear. Timer reset on `play_sound` in `:play` mode only (not reset in `:presence`). Timer fires → leave called, state cleared. Stale token ignored. |
| `AudioPlayer` — `last_user_left` | Leaves immediately in `:play` and `:presence` modes. Starts idle timer in `false` mode with timeout. No-ops in `false` mode with timeout disabled. Ignores call when bot is not in a channel. |
| `AudioPlayer` — `user_joined_channel` | Cancels idle timer. |
| `AudioPlayer` — auto-join | User with `discord_id` in a voice channel → join called, `voice_channel` set, idle timer started (`:play` mode). User not in any channel → error, no join. Actor without `discord_id` → no lookup attempted. Auto-join skipped in `false` mode. |

---

## Out of Scope

- **Auto-join for `!play` Discord commands**: the `!play` command handler already requires `!join` first; that flow was not changed.
- **Per-guild or per-channel idle timeout**: the timeout is global. Future work could make it configurable per guild via DB settings.
- **Idle timeout reset on playback *finish*** (as opposed to *start*): the timer resets when a sound is cast, not when it finishes playing. This means the clock starts as soon as playback is requested, not after the sound ends. For typical usage (sounds are 1–30 seconds) this makes no practical difference.
- **Notifying users before leaving**: the bot does not send a Discord message warning that it is about to leave due to inactivity.
- **`false` mode last-user-leave recheck delay**: the 1.5-second recheck-alone logic in `VoiceRuntime` applies for all modes, including `false`. The idle timer in `false` mode does not start until the recheck confirms the bot is alone.
