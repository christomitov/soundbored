# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Default repo adapter can be overridden per-environment (e.g., prod) to
# compile against Postgres when building the Pro edition.
config :soundboard, :repo_adapter, Ecto.Adapters.SQLite3

# config :soundboard,
#   ecto_repos: [Soundboard.Repo],
#   generators: [timestamp_type: :utc_datetime],
#   token: System.get_env("DISCORD_TOKEN")

# Nostrum config removed - using Nostrum.Bot module instead
# Only ffmpeg path is configured in runtime.exs

# Configures the endpoint
config :soundboard, SoundboardWeb.Endpoint,
  url: [host: "localhost", port: 4000],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SoundboardWeb.ErrorHTML, json: SoundboardWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Soundboard.PubSub,
  live_view: [signing_salt: "9gxiIiqP"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :soundboard, Soundboard.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  soundboard: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  soundboard: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Add MIME types for audio files
config :mime, :types, %{
  "audio/mpeg" => ["mp3"],
  "audio/ogg" => ["ogg"],
  "audio/wav" => ["wav"],
  "audio/x-wav" => ["wav"],
  "audio/x-m4a" => ["m4a"]
}

config :mime, :extensions, %{
  "wav" => "audio/wav"
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Add this near the top of the file
config :soundboard,
  ecto_repos: [Soundboard.Repo]

# Add this somewhere in the file
config :soundboard, Soundboard.Repo,
  database: "priv/static/uploads/database.db",
  pool_size: 5

config :phoenix_live_view,
  flash_timeout: 3000

config :soundboard, SoundboardWeb.Presence, pubsub_server: Soundboard.PubSub

# Add this with your other configs
config :ueberauth, Ueberauth,
  providers: [
    discord: {Ueberauth.Strategy.Discord, [default_scope: "identify"]}
  ]
