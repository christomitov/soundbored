# Spec: Voice Channel Auto-Join on Playback & Idle Auto-Leave

**Status:** Implemented  
**Date:** 2026-04-28  
**Author:** Justin Hart

---

## Summary

Two related quality-of-life improvements to bot voice channel management:

1. **Auto-join on play**: when a user triggers sound playback from the web UI or API and the bot is not in any voice channel, the bot automatically joins the user's current Discord voice channel before playing.
2. **Idle auto-leave**: after no sounds have been played for a configurable period (default: 10 minutes), the bot automatically leaves the voice channel. This supplements the existing "leave when last person departs" behavior.

---

## Motivation

Previously, users had to manually type `!join` in Discord before playing sounds from the web UI. This broke the flow: open the soundboard tab, click a sound, nothing happens, switch to Discord, type `!join`, switch back, click again. The bot also had no way to clean up a lingering voice session after everyone drifted away from a channel.

These two features together make the bot feel self-managing: it follows you in and cleans up after itself.

---

## User-Facing Behavior

### Auto-Join on Play

| Situation | Before | After |
|---|---|---|
| Bot has no voice channel, user clicks a sound | Error: "Bot is not connected to a voice channel. Use !join in Discord first." | Bot joins the user's current voice channel and plays the sound |
| User is not in any voice channel | Error | Same error (no channel to join) |
| Actor is `System` (join/leave sounds) | Error | Same error (no Discord identity to look up) |
| Bot already in a channel | Plays normally | Unchanged |

The auto-join is reactive and on-demand — it does **not** change the presence-based auto-follow behavior controlled by the `AUTO_JOIN` environment variable. These are orthogonal features.

### Idle Auto-Leave

The bot leaves the voice channel after `VOICE_IDLE_TIMEOUT_MINUTES` minutes (default: 10) of no playback activity. "Activity" is defined as a `play_sound` cast arriving at the AudioPlayer — queuing a sound resets the clock.

The idle timer interacts with existing leave behaviors as follows:

| Event | Result |
|---|---|
| `play_sound` cast received | Timer resets to full timeout |
| Bot joins a channel (via `!join`, auto-join, or bootstrap) | Timer starts |
| Bot leaves a channel (any reason) | Timer cancelled |
| Last non-bot user leaves the channel | Existing "leave when alone" logic fires; timer cancelled |
| Idle timer fires | Bot leaves immediately (same as "last person left" behavior) |

---

## Architecture & Design

### Auto-Join Flow

```
Web UI / API → AudioPlayer.play_sound(name, %User{discord_id: ...})
  │
  ▼  (voice_channel is nil)
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
  │                                    schedule idle timer
  │                                    proceed with playback
  │
  └─ :not_found ──► Notifier.error("Bot is not connected... Use !join in Discord first.")
```

The join happens directly inside the `handle_cast` body — state is updated synchronously, and playback proceeds in the same message handler. This avoids any circular-cast problem: `VoiceCommands.join_voice_channel` normally calls `AudioPlayer.set_voice_channel` as a success callback, which would deadlock if called from inside `AudioPlayer`. By calling `Voice.join_channel/2` directly and updating state ourselves, we avoid that dependency entirely.

### Idle Timeout Flow

```
AudioPlayer state: idle_timeout_ref = {timer_ref, token}

set_voice_channel({guild, chan}) → cancel old timer → schedule new timer
play_sound cast              → cancel old timer → schedule new timer (reset)
set_voice_channel(nil, nil)  → cancel timer
{:idle_timeout, token} msg   → leave if token matches active ref, else ignore (stale)
```

The `{ref, token}` pair in `idle_timeout_ref` guards against a race condition: if `Process.cancel_timer` returns `false` (the message already fired and is in the mailbox), the stale message arrives after the new timer is scheduled. The token mismatch causes it to be silently dropped rather than triggering a double-leave.

### Actor Type Change

Previously, `play_sound` actors from the web layer were plain username strings (e.g. `"justin"`), and from the API layer, a map `%{display_name: username, user_id: db_id}`. Neither carried a `discord_id` usable for voice channel lookup.

Both callers now pass the full `%Soundboard.Accounts.User{}` struct. `PlaybackEngine` already handled this type (via `actor_display_name/1` and `actor_user_id/1` pattern matches), so no downstream changes were needed. The new `actor_discord_id/1` private function in `AudioPlayer` extracts the Discord ID for auto-join, and falls back to `:not_found` for strings and maps without `discord_id`.

### Leave Behavior on Idle Timeout

Two approaches were considered:

**A — Leave immediately** (chosen): consistent with the existing "last person left" behavior. The idle timer only fires after 10+ idle minutes, so interrupting in-progress audio is essentially impossible in practice: `reset_idle_timeout` is called on every `play_sound` cast, so any active use resets the clock.

**B — Extend once if playback is in progress**: check `state.current_playback` and reschedule if non-nil. Adds a second code path, a state machine edge, and the risk of indefinite extension if sounds keep queuing just before expiry.

Approach A was chosen for simplicity and behavioral consistency.

### Direct `Voice.leave_channel` vs `VoiceCommands.leave_voice_channel`

`VoiceCommands.leave_voice_channel` would introduce a circular module dependency:
- `VoiceCommands` already calls `AudioPlayer.set_voice_channel` (compile-time dep)
- `AudioPlayer` calling `VoiceCommands` would close the cycle

Instead, `AudioPlayer` calls `Voice.leave_channel/1` directly and updates its own state (clearing `voice_channel`, cancelling the queue). This is consistent with how `VoiceSession.maintain_connection` already calls `Voice.leave_channel` directly.

---

## New Module: `VoicePresence.find_user_voice_channel/1`

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

Reads the `VOICE_IDLE_TIMEOUT_MINUTES` environment variable. Returns the timeout in milliseconds. Follows the same shape as `AutoJoinPolicy`.

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `VOICE_IDLE_TIMEOUT_MINUTES` | `10` | Minutes of inactivity before the bot leaves a voice channel. Set to a higher value (e.g. `60`) if you want the bot to stay around longer. |
| `AUTO_JOIN` | `false` | **Existing, unchanged.** Controls whether the bot proactively follows users into channels on voice state updates. Orthogonal to the on-play auto-join added here. |

---

## Database Changes

**None.**

---

## File Inventory

| File | Action |
|---|---|
| `lib/soundboard/discord/handler/idle_timeout_policy.ex` | **New** — `VOICE_IDLE_TIMEOUT_MINUTES` config reader |
| `lib/soundboard/discord/handler/voice_presence.ex` | **Modify** — add `find_user_voice_channel/1` |
| `lib/soundboard/audio_player.ex` | **Modify** — auto-join logic, idle timeout lifecycle, actor type |
| `lib/soundboard_web/live/support/sound_playback.ex` | **Modify** — pass `%User{}` struct instead of username string |
| `lib/soundboard_web/controllers/api/sound_controller.ex` | **Modify** — pass `%User{}` struct instead of display-name map |
| `test/soundboard/discord/handler/idle_timeout_policy_test.exs` | **New** |
| `test/soundboard/discord/handler/voice_presence_test.exs` | **New** — covers `find_user_voice_channel/1` |
| `test/soundboard_web/audio_player_test.exs` | **Modify** — idle timeout and auto-join tests added |
| `test/soundboard_web/plugs/api_auth_db_token_test.exs` | **Modify** — actor assertion updated |
| `test/soundboard_web/controllers/api/sound_controller_test.exs` | **Modify** — actor assertion updated |
| `test/soundboard_web/live/favorites_live_test.exs` | **Modify** — actor assertion updated |

---

## Testing Strategy

| Layer | What is tested |
|---|---|
| `IdleTimeoutPolicy` | Default (no env var) → 600,000 ms. Custom value. Whitespace trimming. |
| `VoicePresence.find_user_voice_channel` | User found in a guild. User not found. User in guild but no channel. Multi-guild search. Cache unavailable. |
| `AudioPlayer` — idle timeout | Timer scheduled on `set_voice_channel`. Timer cancelled on `set_voice_channel(nil, nil)`. Timer reset on `play_sound`. Timer fires → leave called, state cleared. Stale token ignored. |
| `AudioPlayer` — auto-join | User with `discord_id` in a voice channel → join called, `voice_channel` set, idle timer started. User not in any channel → error, no join. Actor without `discord_id` (e.g. `"System"`) → no lookup attempted. |

---

## Out of Scope

- **Auto-join for `!play` Discord commands**: the `!play` command handler already requires `!join` first; that flow was not changed.
- **Per-guild or per-channel idle timeout**: the timeout is global. Future work could make it configurable per guild via DB settings.
- **Idle timeout reset on playback *finish*** (as opposed to *start*): the timer resets when a sound is cast, not when it finishes playing. This means the clock starts as soon as playback is requested, not after the sound ends. For typical usage (sounds are 1–30 seconds) this makes no practical difference.
- **Notifying users before leaving**: the bot does not send a Discord message warning that it is about to leave due to inactivity.
