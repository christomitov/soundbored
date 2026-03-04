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

# Allow build tooling to opt-out to avoid requiring secrets during image builds.
if config_env() == :prod and is_nil(System.get_env("SKIP_RUNTIME_CONFIG")) do
  # Replace the database_url section with SQLite configuration
  database_path = Path.join(:code.priv_dir(:soundboard), "static/uploads/soundboard_prod.db")

  config :soundboard, Soundboard.Repo,
    database: database_path,
    adapter: Ecto.Adapters.SQLite3,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      case System.get_env("SECRET_KEY_BASE_FILE") do
        file when is_binary(file) and file != "" ->
          case File.read(file) do
            {:ok, key} ->
              String.trim(key)

            {:error, reason} ->
              raise """
              could not read SECRET_KEY_BASE_FILE (#{file}): #{inspect(reason)}
              """
          end

        _ ->
          raise """
          environment variable SECRET_KEY_BASE is missing.
          Provide it via your environment (recommended) or set SECRET_KEY_BASE_FILE to a file path containing the key.
          Generate one with: mix phx.gen.secret OR openssl rand -base64 48
          """
      end

  host = System.get_env("PHX_HOST") || raise("PHX_HOST must be set")

  scheme = System.get_env("SCHEME") || "https"
  callback_url = "#{scheme}://#{host}/auth/discord/callback"

  # Configure endpoint first
  config :soundboard, SoundboardWeb.Endpoint,
    url: [
      scheme: scheme,
      host: host,
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    http: [
      ip: {0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    static_url: [
      host: host,
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    check_origin: false,
    force_ssl: scheme == "https",
    secret_key_base: secret_key_base,
    session: [
      store: :cookie,
      key: "_soundboard_key",
      signing_salt: secret_key_base
    ]

  # Configure Ueberauth
  config :ueberauth, Ueberauth,
    providers: [
      discord: {Ueberauth.Strategy.Discord, [default_scope: "identify"]}
    ]

  # Configure Discord OAuth
  config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
    client_id: System.get_env("DISCORD_CLIENT_ID"),
    client_secret: System.get_env("DISCORD_CLIENT_SECRET"),
    redirect_uri: callback_url

  # Configure Discord bot token
  discord_token =
    System.get_env("DISCORD_TOKEN") ||
      raise """
      environment variable DISCORD_TOKEN is missing.
      Please set your Discord bot token.
      """

  # Store token for application use (bot will fetch it from here)
  voice_rtp_probe =
    System.get_env("VOICE_RTP_PROBE", "false")
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes", "on"]))

  voice_rtp_probe_timeout_ms =
    case Integer.parse(System.get_env("VOICE_RTP_PROBE_TIMEOUT_MS", "6000")) do
      {value, ""} when value > 0 -> value
      _ -> 6_000
    end

  eda_dave =
    System.get_env("EDA_DAVE", "true")
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes", "on"]))

  config :soundboard,
    discord_token: discord_token,
    voice_rtp_probe: voice_rtp_probe,
    voice_rtp_probe_timeout_ms: voice_rtp_probe_timeout_ms

  if is_nil(System.find_executable("ffmpeg")) do
    raise "ffmpeg not found in PATH. Please install ffmpeg."
  end

  config :eda,
    token: discord_token,
    dave: eda_dave

  # Configure logger for production
  config :logger,
    # Set minimum log level to debug to see IO.puts
    level: :debug,
    compile_time_purge_matching: [
      # Don't purge debug logs
      [level_lower_than: :debug]
    ]

  config :logger, :console,
    format: "$time $metadata[$level] $message\n",
    metadata: [:request_id, :error],
    # Enable colors for better visibility
    colors: [enabled: true]

  # Keep stacktraces in production for better error reporting
  config :phoenix,
    stacktrace_depth: 20,
    plug_init_mode: :runtime

  config :soundboard, :env, :prod
end
