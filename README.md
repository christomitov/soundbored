# Soundbored

Soundbored is an unlimited, no-cost, self-hosted soundboard for Discord. It allows you to play sounds in a voice channel.

[Prerequisites](#prerequisites)
[Setup](#setup)
[Deployment](#deployment)
[Usage](#usage)
[Changelog](#changelog)

<img width="1470" alt="Screenshot 2025-01-08 at 1 12 08 PM" src="https://github.com/user-attachments/assets/6e2cf7ff-c19f-4405-bde0-b3f0daa4d84c" />



## Prerequisites

1. A bot token with the following permissions:

- Send Messages
- Read Message History
- View Channels
- Connect
- Speak

**NOTE: Also remember to go under Bot and select PRESENCE INTENT, SERVER MEMBERS INTENT and MESSAGE CONTENT INTENT**

You then need to invite the bot to your server by going to `Oauth2`, checking `bot` and then checking the same permisions as above. You can then take the generated URL at the bottom and invite the bot.

2. If you want to host publicly, a domain name is required so people can access your Soundbored instance.

3. Under `Redirect` in `Oauth2` put your domain like `https://your.domain.com/auth/discord/callback` in the Discord Developer Portal. Copy the `Client ID` and `Client Secret` as you will need them for the environment variables below.

4. You will need to host this publicly somewhere for other users to be able to use it. I recommend using [Digital Ocean](https://www.digitalocean.com/) for this as its cheap and you can deploy Docker images directly.


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


## Deployment

The application is containerized and published to Docker Hub. You can pull it with `docker pull christom/soundbored:latest`. Or run immediately in localhost with: `docker run -d -p 4000:4000 --env-file ./.env christom/soundbored`.

### Local Deployment
```bash
# Create .env file from example
cp .env.example .env

# Edit .env with your values, make sure:
PHX_HOST=localhost
SCHEME=http


# With Docker Image, run locally (no Caddy)
docker run -d -p 4000:4000 --env-file ./.env christom/soundbored

# Or with Project cloned, Run locally (no Caddy)
docker compose up
```

### Production Deployment
```bash
# Create .env file from example
cp .env.example .env

# Edit .env with your values, make sure:
PHX_HOST=your.domain.com
SCHEME=https

# Modiy the Caddyfile
your.domain.com {
    reverse_proxy soundbored:4000
}

# Pull the latest image
docker pull christom/soundbored:latest

# Run in production (with Caddy)
docker compose -f docker-compose.prod.yml up -d
```

The deployment mode is automatically determined by the PHX_HOST value:
- If PHX_HOST=localhost: Runs without Caddy, accessible at http://localhost:4000
- If PHX_HOST=domain.com: Runs with Caddy, handles SSL automatically

Note: Make sure to create a Caddyfile in the same directory as your docker-compose.prod.yml file. The Caddyfile should contain your domain configuration. For example:

```
your.domain.com {
    reverse_proxy soundbored:4000
}
```

Replace `your.domain.com` with your actual domain name. Caddy will automatically handle SSL certificate generation for your domain.


## Usage

After inviting the bot to your server, join a voice channel and type `!join` to have the bot join the voice channel. Type `!leave` to have the bot leave. You can upload sounds to Soundbored and trigger them there and they will play in the voice channel.


## Changelog

### v1.1.1 (2025-01-15)

#### ✨ New Features
- Added random sound button
- Allow ability to click tags inside sounds for filtering

#### 🐛 Bug Fixes
- Fixed bug where if you uploaded a sound and edited its name before uploading a file it would crash

### v1.1.0 (2025-01-12)

#### ✨ New Features
- Implemented join/leave sound notifications
- Added Discord avatar support for member profiles
- Added week selector functionality to statistics page

#### 🐛 Bug Fixes
- Fixed mobile menu navigation issues on statistics page
- Fixed statistics page not updating in realtime
- Fixed styling issues on stats page