import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :soundboard, Soundboard.Repo,
  adapter: Ecto.Adapters.Exqlite,
  database: Path.expand("../soundboard_test.db", Path.dirname(__ENV__.file)),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1,
  busy_timeout: 5000,
  journal_mode: :wal

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :soundboard, SoundboardWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZQxhSuZctCJ5Sv3XJfvIJCTRjIaXE2SFuOUR0STQRho6P74FL1PIP6esgMcjscQ0",
  server: false

# In test we don't send emails
config :soundboard, Soundboard.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning
# Configure the console backend
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :file, :line]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :soundboard, :sql_sandbox, true

config :soundboard, env: :test

config :soundboard, Soundboard.PubSub,
  adapter: Phoenix.PubSub.PG2,
  name: Soundboard.PubSub

# Configure Nostrum for test environment
# Using a dummy token that won't connect to Discord
config :nostrum,
  token: System.get_env("DISCORD_TOKEN") || "NzI5MjM0NzI5MzQ3MjM0.dummy.tokenfortestingpurposes",
  num_shards: :manual,
  session_controller_pid: self(),
  dev: false
