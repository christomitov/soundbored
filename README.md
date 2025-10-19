# Soundbored
[![Coverage Status](https://coveralls.io/repos/github/christomitov/soundbored/badge.svg?branch=main)](https://coveralls.io/github/christomitov/soundbored?branch=main)
[![Build Status](https://github.com/christomitov/soundbored/workflows/CI%2FCD%20Pipeline/badge.svg)](https://github.com/christomitov/soundbored/actions)

Soundbored is an unlimited, no-cost, self-hosted soundboard for Discord. It allows you to play sounds in a voice channel.

[Hexdocs](https://christomitov.github.io/soundbored/)

<img width="1468" alt="Screenshot 2025-01-18 at 1 26 07 PM" src="https://github.com/user-attachments/assets/4a504100-5ef9-47bc-b406-35b67837e116" />

### CLI Companion
Install the cross-platform CLI with `npm i -g soundbored` for quick automation. Source: [christomitov/soundbored-cli](https://github.com/christomitov/soundbored-cli).

## Quickstart

1. Copy the sample environment and set the minimum values:
   ```bash
   cp .env.example .env
   # Required for local testing
   # DISCORD_TOKEN=...
   # DISCORD_CLIENT_ID=...
   # DISCORD_CLIENT_SECRET=...
   # API_TOKEN=choose_a_secret
   # PHX_HOST=localhost
   # SCHEME=http
   ```
2. Run the published container:
   ```bash
   docker run -d -p 4000:4000 --env-file ./.env christom/soundbored
   ```
3. Visit http://localhost:4000, invite the bot, and trigger your first sound.

> Create the bot in the [Discord Developer Portal](https://discord.com/developers/applications), enable **Presence**, **Server Members**, and **Message Content** intents, and grant Send Messages, Read History, View Channels, Connect, and Speak permissions when you invite it.

### Discord App Setup

1. In the Discord Developer Portal, open your application and go to **Bot** → enable **Presence**, **Server Members**, and **Message Content** intents.
2. Still in the portal, go to **OAuth2 → Redirects** and add every URL that will serve Soundbored to the **Redirects** list. For example:
   - `http://localhost:4000/auth/discord/callback` (local development)
   - `https://your.domain.com/auth/discord/callback` (production, replace with your domain)
   Discord requires the redirect in your app configuration to match exactly what the browser uses during login; otherwise, OAuth will fail.
3. Copy the **Client ID** and **Client Secret** from the same page—add them to your `.env` file as `DISCORD_CLIENT_ID` and `DISCORD_CLIENT_SECRET`.
4. Use **OAuth2 → URL Generator** (scope `bot`) to produce the invite link with the permissions listed above.

## Local Development

```bash
mix setup        # Fetch deps, prepare DB, build assets
mix phx.server   # or iex -S mix phx.server
```

Useful commands:
- `mix test` – run the test suite (coverage via `mix coveralls`).
- `mix credo --strict` – linting.
- `mix dialyzer` – type analysis.

`docker compose up` also works for a containerized local run; it respects the same `.env` configuration.

## Environment Variables

All available keys live in `.env.example`. Configure the ones that match your setup:

| Variable | Required | Purpose |
| --- | --- | --- |
| `DISCORD_TOKEN` | ✔ | Bot token used to play audio in voice channels. |
| `DISCORD_CLIENT_ID` / `DISCORD_CLIENT_SECRET` | ✔ | OAuth credentials for Discord login. |
| `API_TOKEN` | ✔ | Shared bearer token for the REST API. |
| `SECRET_KEY_BASE` | ✔ | Signing/encryption secret; generate via `mix phx.gen.secret`. |
| `PHX_HOST` | ✔ | Hostname the app advertises (`localhost` for local runs). |
| `SCHEME` | ✔ | `http` locally, `https` in production. |
| `BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD` | optional | Protect the UI with HTTP basic auth. |
| `AUTO_JOIN` | optional | Set to `true` to let the bot auto-join voice channels. |

## Deployment

The application is published to Docker Hub as `christom/soundbored`.

### Simple Docker Host
```bash
docker pull christom/soundbored:latest
docker run -d -p 4000:4000 --env-file ./.env christom/soundbored
```
If you place the container behind your own reverse proxy, set `PHX_HOST` and `SCHEME` in `.env` to match the external URL and terminate TLS in your proxy. No additional compose files are required.

## Usage

After inviting the bot to your server, join a voice channel and type `!join` to have the bot join the voice channel. Type `!leave` to have the bot leave. You can upload sounds to Soundbored and trigger them there and they will play in the voice channel.

The bot is also able to auto-join and auto-leave voice channels. This is controlled by the `AUTO_JOIN` environment variable. Leave it unset (or `false`) to disable, or set it to `true` to have the bot join voice channels with members and auto-leave when the last user leaves.

## API

The API is used to trigger sounds from other applications. It is protected by the API_TOKEN in the .env file. The API has the following endpoints:

```
# Get list of sounds to find the ID
curl https://soundboardurl.com/api/sounds \
  -H "Authorization: Bearer API_TOKEN"

# Play a sound by ID
curl -X POST https://soundboardurl.com/api/sounds/123/play \
  -H "Authorization: Bearer API_TOKEN"
```


## Changelog

### v1.6.0 (2025-10-01)

#### ✨ New Features
- New consolidated `Settings` view replaces the standalone API tokens screen and keeps token creation, revocation, and inline API examples in one place.
- Stats dashboard adds a week picker, richer recent activity stream, and refreshed layout under the new name “Stats”.
- “Play Random” now respects whatever filters are active, pulling from the current search results or selected tags only.

#### ⚙️ Improvements
- Shared tag components and modal tweaks streamline sound management and reduce layout shifts.
- Navigation highlights the active page and keeps Settings aligned with the rest of the app.
- Mobile refinements across the main board and settings eliminate horizontal scrolling and polish button spacing.
- Basic Auth now quietly skips enforcement when credentials are not configured instead of blocking the UI.

#### 🧪 Tests & Quality
- Expanded LiveView coverage for the new Settings page, Stats interactions, and filtered random playback.
- Updated CI workflow and Dependabot configuration keep coverage and dependency checks automated.

#### 📦 Dependencies
- Bumped Phoenix stack and related dependencies, plus cleaned up mix configuration and docs to match the new release.

### v1.5.0 (2025-09-14)

#### ✨ New Features
- User-scoped API tokens with DB storage (generate/revoke in Settings > API Tokens).
- API requests authenticated via `Authorization: Bearer <token>` are attributed to the token’s user and increment stats accordingly.
- In-app API help with copy-to-clipboard curl commands that auto-fill your site URL and token.
- Added Settings link in the navbar for quick access.
- Released a new CLI for easier local and CI integrations.

#### ⚙️ Improvements
- Search bar: reduced debounce to 200ms and added inline spinner while searching.
- Recent Plays: fixed item “disappearing” by using stable DB ids and deterministic ordering; clicked items now bump to the top correctly.

#### 🧪 Tests & Quality
- Added tests for API token lifecycle, API auth with DB tokens, Basic Auth, and the Settings LiveView.
- Coverage improved to ~96% (via mix coveralls).

#### 🔁 Compatibility
- Legacy env `API_TOKEN` remains supported for a transition period (logs deprecation); DB tokens are the preferred path going forward.

### v1.4.0 (2025-08-22)

#### 🐛 Bug Fixes
- Fixed sounds not playing due to Discord API changes
- Optimized audio playback for faster sound loading and playback

#### 🔧 Maintenance
- Updated all dependencies to latest versions

### v1.3.0 (2025-02-18)

#### ✨ New Features
- Added API to get and trigger sounds.
- Added "stop all sounds" button.
- Implemented auto leave and join voice channels.
- Sorting sounds alphabetically
- Added ability to disable basic auth (just comment out BASIC_AUTH_USERNAME and BASIC_AUTH_PASSWORD in .env)

### v1.2.0 (2025-01-18)

#### ✨ New Features
- Added random sound button.
- Added ability to add and trigger sounds from a URL.
- Allow ability to click tags inside sound Cards for filtering.
- Show what user uploaded a sound in the sound Card.

#### 🐛 Bug Fixes
- Fixed bug where if you uploaded a sound and edited its name before uploading a file it would crash.
- Fixed bug where changing an uploaded sound name created a new sound in entry and didn't update the old.

### v1.1.0 (2025-01-12)

#### ✨ New Features
- Implemented join/leave sound notifications
- Added Discord avatar support for member profiles
- Added week selector functionality to statistics page

#### 🐛 Bug Fixes
- Fixed mobile menu navigation issues on statistics page
- Fixed statistics page not updating in realtime
- Fixed styling issues on stats page
