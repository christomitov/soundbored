# Soundbored

Soundbored is an unlimited, no-cost, self-hosted soundboard for Discord. It allows you to play sounds in a voice channel.

<img width="1470" alt="Screenshot 2025-01-08 at 1 12 08 PM" src="https://github.com/user-attachments/assets/6e2cf7ff-c19f-4405-bde0-b3f0daa4d84c" />

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

The application is containerized and published to Docker Hub. You can pull it with `docker pull christom/soundbored:latest`.

### Local Deployment
```bash
# Create .env file from example
cp .env.example .env

# Edit .env with your values, make sure:
PHX_HOST=localhost
SCHEME=http


# with the docker image pulled, run locally (no Caddy)
docker run --env-file ./.env christom/soundbored

# Run locally (no Caddy)
docker compose up
```

### Production Deployment
```bash
# Create .env file from example
cp .env.example .env

# Edit .env with your values, make sure:
PHX_HOST=your.domain.com
SCHEME=https

# Create a Caddyfile
echo "your.domain.com {
    reverse_proxy soundbored:4000
}" > Caddyfile

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