# Spec: YouTube Video Playback via Discord Bot Command

**Status:** Draft  
**Date:** 2026-03-07  
**Author:** —

---

## Summary

Add a `!play <youtube_url>` Discord bot command that extracts the audio from a YouTube video and plays it through the bot's current voice channel. This is an ephemeral, on-demand playback — it does **not** save the YouTube audio as a permanent sound in the library.

---

## Motivation

Users currently play pre-uploaded sounds (local files or direct URLs) via the soundboard. There is no way to quickly share and play a YouTube video's audio in voice chat without first downloading, converting, and uploading it. A `!play` command eliminates that friction.

---

## User-Facing Behavior

### Commands

| Command | Description |
|---|---|
| `!play <youtube_url>` | Extract audio from the YouTube URL and play it in the bot's current voice channel. |
| `!play <youtube_url> <volume>` | Same as above, with an explicit volume (0.0–1.5, default 1.0). |
| `!stop` | Stop whatever is currently playing (already exists — no change). |

### Responses

| Scenario | Bot Reply |
|---|---|
| Success | 🎵 Now playing: `<video_title>` |
| Bot not in a voice channel | "I'm not in a voice channel. Use `!join` first." |
| Invalid / unsupported URL | "That doesn't look like a valid YouTube URL." |
| yt-dlp extraction fails | "Failed to fetch audio from that URL. It may be private, age-restricted, or region-locked." |
| Already playing (interrupt) | Stops current sound, starts YouTube audio (existing interrupt behavior). |

---

## Architecture & Design

### High-Level Flow

```
Discord message "!play <url>"
  │
  ▼
CommandHandler.handle_message/1          ← parse command, validate URL format
  │
  ▼
Soundboard.YouTube.Extractor            ← NEW module: call yt-dlp, return audio stream URL + metadata
  │
  ▼
AudioPlayer.play_youtube/3               ← NEW public API on AudioPlayer GenServer
  │
  ▼
PlaybackQueue / PlaybackEngine           ← reuse existing queue & engine (plays URL type)
  │
  ▼
Discord Voice (EDA)                      ← ffmpeg reads the stream URL, sends RTP
```

### New Modules

#### 1. `Soundboard.YouTube.Extractor`

Wraps the `yt-dlp` CLI directly via `System.cmd/3`.

**Responsibilities:**
- Validate that a URL is a supported YouTube link via a regex matching `youtube.com/watch?v=`, `youtu.be/`, `youtube.com/shorts/`.
- Extract metadata + stream URL in a **single** `yt-dlp` invocation using combined flags: `yt-dlp --get-title --get-url --get-duration -f bestaudio --no-playlist <url>`.
- Parse the multi-line stdout (line 1: title, line 2: stream URL, line 3: duration) into a struct.
- Enforce a maximum duration (configurable, default: 10 minutes / 600s) to prevent abuse.
- Wrap the call in `Task.async` + `Task.yield/2` with a configurable timeout (default: 15s) to avoid hanging on slow networks or unresponsive URLs.
- Return `{:ok, %{stream_url: url, title: title, duration_seconds: integer}}` or `{:error, reason}` with user-friendly messages derived from stderr.

**Key design decisions:**
- Always use the list-of-args form of `System.cmd/3` — never shell interpolation — to prevent command injection.
- `--no-playlist` flag to prevent accidentally queuing an entire playlist.
- `-f bestaudio` to get an audio-only stream URL that ffmpeg can consume directly.
- Binary path resolved via `Application.get_env(:soundboard, :ytdlp_executable, :system)`, matching the existing `:ffmpeg_executable` pattern.
- Availability check via `System.find_executable("yt-dlp")` or configured path, cached in `persistent_term` on first call.
- In tests, the module can be mocked via `Mox` or by making the system-cmd call go through a configurable function/module.

**Public API:**
```elixir
@spec extract(String.t()) :: {:ok, extraction()} | {:error, String.t()}
@spec valid_url?(String.t()) :: boolean()
@spec available?() :: boolean()
```

### Modified Modules

#### `Soundboard.Discord.Handler.CommandHandler`

Add a new clause:

```elixir
def handle_message(%{content: "!play " <> url_and_args} = msg)
```

- Parse the URL (first token) and optional volume (second token).
- Validate URL format via `YouTube.Extractor.valid_youtube_url?/1`.
- Check that the bot is in a voice channel (`AudioPlayer.current_voice_channel/0`).
- On validation pass, call `AudioPlayer.play_youtube(url, volume, actor)`.
- Reply with an appropriate Discord message (see table above).

#### `Soundboard.AudioPlayer` (GenServer)

Add a new public function and cast:

```elixir
def play_youtube(url, volume \\ 1.0, actor)
```

Internally sends `{:play_youtube, url, volume, actor}`. The `handle_cast` will:
1. Call `YouTube.Extractor.extract(url)`.
2. On success, build a play request (similar to `PlaybackQueue.build_request/3` but using the extracted stream URL and supplied volume directly, bypassing `SoundLibrary`).
3. Enqueue via `PlaybackQueue.enqueue/3` — reusing all existing interrupt/retry logic.

#### `Soundboard.AudioPlayer.PlaybackEngine`

No changes expected. The engine already supports `:url` play type, and the extracted stream URL is a direct audio URL that ffmpeg handles natively.

#### `Soundboard.AudioPlayer.PlaybackQueue`

Add a new `build_youtube_request/4` function (or extend `build_request`) that creates a play request from a raw URL + volume instead of looking up `SoundLibrary`:

```elixir
@spec build_youtube_request({String.t(), String.t()}, String.t(), number(), term()) ::
        {:ok, play_request()}
def build_youtube_request({guild_id, channel_id}, stream_url, volume, actor)
```

The `sound_name` field in the request will be set to the video title (for display in notifications).

### Stats / Tracking

YouTube plays are **not** tracked in the `stats.plays` table (they aren't library sounds). The `PlaybackEngine` already skips tracking for system users — we can use a similar mechanism, or simply not call `track_play_if_needed` for YouTube plays. The `Notifier.sound_played/2` broadcast will still fire so the LiveView shows "User played <video title>".

---

## Dependencies

### Hex

**None.** We wrap `yt-dlp` directly via `System.cmd/3` — no third-party Hex packages needed.

We evaluated `exyt_dlp` (~> 0.1.6) and decided against it. The library is a thin pass-through to `System.cmd("yt-dlp", params)` with no timeout support, no combined-flag calls, and opaque error handling (`:invalid_youtube_url_or_params` for everything). Our own wrapper is ~60 lines, gives us full control, and avoids a low-activity single-maintainer dependency.

### System: `yt-dlp`

`yt-dlp` is a **system dependency** that must be installed on the host.

| Environment | Installation |
|---|---|
| Local dev | `brew install yt-dlp` / `pip install yt-dlp` |
| Docker | Add `RUN pip install yt-dlp` (or grab the static binary) to the Dockerfile |

The application should gracefully degrade: if `yt-dlp` is not found, `!play` replies with "YouTube playback is not available (yt-dlp not installed)." Binary path resolved via `Application.get_env(:soundboard, :ytdlp_executable, :system)`, matching the existing `:ffmpeg_executable` pattern in `PlaybackEngine`.

---

## Configuration

Add to `config/config.exs` (or runtime config):

```elixir
config :soundboard, :ytdlp_executable, :system          # :system | false | "/path/to/yt-dlp"
config :soundboard, :youtube_max_duration_seconds, 600   # 10 minutes
config :soundboard, :ytdlp_timeout_ms, 15_000            # extraction timeout
```

---

## Database Changes

**None.** YouTube plays are ephemeral and not persisted.

---

## File Inventory (new & changed)

| File | Action |
|---|---|
| `lib/soundboard/youtube/extractor.ex` | **New** — yt-dlp wrapper |

| `lib/soundboard/discord/handler/command_handler.ex` | **Modify** — add `!play` clause |
| `lib/soundboard/audio_player.ex` | **Modify** — add `play_youtube/3` cast |
| `lib/soundboard/audio_player/playback_queue.ex` | **Modify** — add `build_youtube_request/4` |
| `Dockerfile` | **Modify** — install `yt-dlp` |
| `config/config.exs` | **Modify** — add youtube config keys |
| `test/soundboard/youtube/extractor_test.exs` | **New** — covers extraction + URL validation |
| `test/soundboard/discord/handler/command_handler_test.exs` | **Modify** — add `!play` tests |
| `test/soundboard/audio_player_test.exs` | **Modify** — add youtube cast tests |

---

## Security Considerations

- **Input sanitization:** The YouTube URL is passed as an argument to `System.cmd/3`. Use the list-of-args form (`System.cmd("yt-dlp", [args...])`) — never shell interpolation — to prevent command injection.
- **Duration cap:** Enforce the max duration to prevent a user from streaming a 10-hour video and monopolizing the voice channel.
- **Rate limiting:** (Future / optional) Consider a per-user cooldown on `!play` to prevent spam. Not in scope for v1 but worth noting.
- **No disk writes:** The stream URL approach means no temp files accumulate on the server.

---

## Testing Strategy

| Layer | What to test |
|---|---|
| `YouTube.Extractor` | URL validation (valid/invalid/edge cases: `watch?v=`, `youtu.be/`, shorts, playlist URLs rejected, non-YouTube rejected). Mock `System.cmd` to test parse logic for yt-dlp stdout. Timeout handling. Duration enforcement. Missing binary. |
| `CommandHandler` | `!play` with valid URL dispatches to `AudioPlayer`. `!play` with garbage URL returns error message. `!play` with no args returns usage hint. Bot not in channel returns error. |
| `AudioPlayer` | `play_youtube` cast flows through to `PlaybackQueue`. Integration with mock voice. |
| Manual / integration | End-to-end: bot in voice → `!play https://youtu.be/dQw4w9WgXcQ` → audio plays in Discord. |

---

## Out of Scope (future enhancements)

- Saving a YouTube sound to the library permanently ("!save" command).
- Queue / playlist support (multiple `!play` commands queued in order).
- Playback controls (`!pause`, `!resume`, `!skip`).
- Playing from other platforms (SoundCloud, Spotify, etc.).
- Web UI integration (play YouTube from the LiveView).
- Now-playing status / progress indicator in Discord or the web UI.

---

## Open Questions

1. **Should `!play` also accept non-YouTube URLs?** yt-dlp supports hundreds of sites. We could allow any yt-dlp-supported URL, or restrict to YouTube only for v1. Restricting is simpler and safer — recommend YouTube-only for now.
2. **Should the extraction happen in the `CommandHandler` (before casting to `AudioPlayer`) or inside the `AudioPlayer` GenServer?** Doing it in a Task spawned by `CommandHandler` keeps the AudioPlayer GenServer responsive. However, the current flow already uses `Task.async` inside `PlaybackQueue.start_playback/2`, so doing extraction inside the AudioPlayer cast is consistent. **Recommendation:** Extract in the AudioPlayer cast (inside the spawned playback Task) so the command handler remains fast and the reply can be sent immediately ("⏳ Fetching audio…").
3. **Max duration default?** 10 minutes seems reasonable. Should this be configurable per-guild or global? **Recommendation:** Global config for v1.
