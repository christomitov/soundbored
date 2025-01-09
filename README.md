# Soundbored

Soundbored is an unlimited, no-cost, self-hosted soundboard for Discord. It allows you to play sounds in a voice channel.

## Prerequisites

1. A bot token with the following permissions:

- Send Messages
- Read Message History
- View Channels
- Connect
- Speak

You then need to invite the bot to your server by going to `Oauth2`, checking `bot` and then checking the same permisions as above. You can then take the generated URL at the bottom and invite the bot.

2. A domain name so people can access your Soundbored instance.

3. Under `Redirect` in `Oauth2` put your domain like `https://your.domain.com/auth/discord/callback` in the Discord Developer Portal. Copy the `Client ID` and `Client Secret` as you will need them for the environment variables below.

4. Edit the `Caddyfile` if you're going to host publicly, and change `your.domain.com` accordingly.

5. You will need to host this publicly somewhere for other users to be able to use it. I recommend using [Digital Ocean](https://www.digitalocean.com/) for this as its cheap and you can deploy Docker images directly.

## Host Locally
Run locally with:

`docker compose up`

The default url will be `http://localhost:4000` so make sure to set that in the redirect URLs above so you can authorize your Discord user.

## Host Publicly
Run publicly with:

`docker compose --profile caddy up`

## Setup
The Docker needs the following environment variables, check .env.example:

```
DISCORD_TOKEN=your_actual_discord_token
DISCORD_CLIENT_ID=your_actual_client_id
DISCORD_CLIENT_SECRET=your_actual_client_secret
# Change this to your domain or to localhost if you're running locally
PHX_HOST=your.domain.com
# change this to http if running locally
SCHEME=https
# Change these to password protect your soundboard
BASIC_AUTH_USERNAME=admin
BASIC_AUTH_PASSWORD=admin
```

## Usage

After inviting the bot to your server, join a voice channel and type `!join` to have the bot join the voice channel. Type `!leave` to have the bot leave. You can upload sounds to Soundbored and trigger them there and they will play in the voice channel.




