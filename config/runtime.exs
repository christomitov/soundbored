import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/soundboard start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :soundboard, SoundboardWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Replace the database_url section with SQLite configuration
  database_path = Path.join(:code.priv_dir(:soundboard), "static/uploads/soundboard_prod.db")

  config :soundboard, Soundboard.Repo,
    database: database_path,
    adapter: Ecto.Adapters.SQLite3,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || raise "PHX_HOST must be set"
  port = String.to_integer(System.get_env("PORT") || "4000")
  scheme = System.get_env("SCHEME") || "https"

  config :soundboard, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :soundboard, SoundboardWeb.Endpoint,
    url: [host: host, port: port, scheme: scheme],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    check_origin: [
      "#{scheme}://#{host}",
      "#{scheme}://#{host}:#{port}",
      "http://#{host}",
      "http://#{host}:#{port}"
    ],
    secret_key_base: secret_key_base,
    debug_errors: true,
    code_reloader: false,
    server: true

  # Add this to force the scheme to match the environment variable
  if scheme == "http" do
    config :soundboard, SoundboardWeb.Endpoint,
      force_ssl: false,
      https: nil
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :soundboard, SoundboardWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :soundboard, SoundboardWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :soundboard, Soundboard.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # Remove duplicate ffmpeg check and consolidate Nostrum config
  discord_token =
    System.get_env("DISCORD_TOKEN") ||
      raise """
      environment variable DISCORD_TOKEN is missing.
      Please set your Discord bot token.
      """

  # Single Nostrum configuration block
  config :nostrum,
    token: discord_token,
    gateway_intents: [
      :guilds,
      :guild_messages,
      :message_content,
      :guild_voice_states,
      :guild_members
    ],
    num_shards: :auto,
    cache_pools: [
      {Nostrum.Cache.GuildCache.ETS, []}
    ]

  # Single ffmpeg check
  case System.cmd("which", ["ffmpeg"]) do
    {path, 0} ->
      config :nostrum, ffmpeg: String.trim(path)

    _ ->
      raise "ffmpeg not found in PATH. Please install ffmpeg."
  end

  # Configure logger for production
  config :logger,
    # Set minimum log level
    level: :info,
    backends: [:console],
    compile_time_purge_matching: [
      # Only purge debug logs
      [level_lower_than: :info]
    ]

  config :logger, :console,
    format: "$time $metadata[$level] $message\n",
    metadata: [:request_id, :error]

  # Keep stacktraces in production for better error reporting
  config :phoenix,
    stacktrace_depth: 20,
    plug_init_mode: :runtime

  # Add this configuration block
  config :ueberauth, Ueberauth.Strategy.Discord,
    callback_url: "#{scheme}://#{host}:#{port}/auth/discord/callback"
end
