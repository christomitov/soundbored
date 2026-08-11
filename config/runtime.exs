import Config
import Dotenvy

env_dir_prefix = System.get_env("RELEASE_ROOT") || Path.expand(".")

source!([
  Path.absname(".env", env_dir_prefix),
  Path.absname(".#{config_env()}.env", env_dir_prefix),
  Path.absname(".#{config_env()}.overrides.env", env_dir_prefix),
  System.get_env()
])

# PHX_HOST must be a hostname only for Endpoint url[:host]. Allow "host:port"
# in env for convenience and split it.
parse_phx_host = fn host_raw ->
  host_raw = host_raw |> to_string() |> String.trim()

  case Regex.run(~r/^(.+):(\d+)$/, host_raw) do
    [_, host, port_str] -> {host, String.to_integer(port_str)}
    _ -> {host_raw, nil}
  end
end

public_host = fn host, port, scheme ->
  default_port? =
    (scheme == "https" and port in [443, nil]) or
      (scheme == "http" and port in [80, nil])

  if default_port? or is_nil(port) do
    host
  else
    "#{host}:#{port}"
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/soundboard start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if env!("PHX_SERVER", :boolean, false) do
  config :soundboard, SoundboardWeb.Endpoint, server: true
end

if config_env() == :dev do
  {host, host_port} = parse_phx_host.(env!("PHX_HOST", :string!, "localhost"))
  scheme = env!("SCHEME", :string!, "http")
  port = host_port || env!("PORT", :integer, 4000)
  callback_url = "#{scheme}://#{public_host.(host, port, scheme)}/auth/discord/callback"
  discord_token = env!("DISCORD_TOKEN", :string!, nil)
  client_id = env!("DISCORD_CLIENT_ID", :string!, nil)
  client_secret = env!("DISCORD_CLIENT_SECRET", :string!, nil)
  eda_dave = env!("EDA_DAVE", :boolean, true)
  voice_rtp_probe = env!("VOICE_RTP_PROBE", :boolean, false)
  voice_rtp_probe_timeout_ms = env!("VOICE_RTP_PROBE_TIMEOUT_MS", :integer, 6_000)

  secret_key_base =
    case env!("SECRET_KEY_BASE", :string!, nil) do
      value when is_binary(value) and byte_size(value) >= 64 ->
        value

      value when is_binary(value) ->
        :crypto.hash(:sha512, value)
        |> Base.encode64(padding: false)

      _ ->
        nil
    end

  bind_ip =
    case env!("BIND_IP", :string!, "127.0.0.1")
         |> String.to_charlist()
         |> :inet.parse_address() do
      {:ok, ip_tuple} -> ip_tuple
      _ -> {127, 0, 0, 1}
    end

  endpoint_overrides = [
    url: [host: host, port: port, scheme: scheme],
    http: [ip: bind_ip, port: port]
  ]

  endpoint_overrides =
    if is_binary(secret_key_base) do
      Keyword.put(endpoint_overrides, :secret_key_base, secret_key_base)
    else
      endpoint_overrides
    end

  config :soundboard, SoundboardWeb.Endpoint, endpoint_overrides

  config :ueberauth, Ueberauth.Strategy.Discord.OAuth,
    client_id: client_id,
    client_secret: client_secret,
    redirect_uri: callback_url

  ffmpeg_available = not is_nil(System.find_executable("ffmpeg"))

  unless ffmpeg_available do
    IO.warn(
      "ffmpeg not found in PATH. Voice playback features will be unavailable until ffmpeg is installed."
    )
  end

  required_guild_id = env!("DISCORD_REQUIRED_GUILD_ID", :string, nil)

  required_role_ids =
    "DISCORD_REQUIRED_ROLE_IDS"
    |> env!(:string, "")
    |> String.split(",", trim: true)

  role_recheck_interval_seconds = env!("DISCORD_ROLE_RECHECK_INTERVAL_SECONDS", :integer, 900)

  ytdlp_executable =
    case env!("YTDLP_PATH", :string, nil) do
      path when is_binary(path) and path != "" -> path
      _ -> :system
    end

  youtube_cookies_path =
    env!("YOUTUBE_COOKIES_PATH", :string, "priv/youtube/cookies.txt")

  config :soundboard,
    discord_token: discord_token,
    voice_rtp_probe: voice_rtp_probe,
    voice_rtp_probe_timeout_ms: voice_rtp_probe_timeout_ms,
    ffmpeg_available: ffmpeg_available,
    required_guild_id: required_guild_id,
    required_role_ids: required_role_ids,
    role_recheck_interval_seconds: role_recheck_interval_seconds,
    ytdlp_executable: ytdlp_executable,
    ytdlp_managed_path: "priv/bin/yt-dlp",
    ytdlp_auto_download: true,
    youtube_cookies_path: youtube_cookies_path

  config :eda,
    token: discord_token,
    dave: eda_dave
end

# Allow build tooling to opt-out to avoid requiring secrets during image builds.
if config_env() == :prod and is_nil(env!("SKIP_RUNTIME_CONFIG", :string, nil)) do
  port = env!("PORT", :integer, 4000)

  if max_bytes = env!("MAX_UPLOAD_BYTES", :integer, nil) do
    config :soundboard, max_upload_bytes: max_bytes
  end

  database_path = "/app/priv/db/soundboard_prod.db"

  config :soundboard, Soundboard.Repo,
    database: database_path,
    adapter: Ecto.Adapters.SQLite3,
    pool_size: env!("POOL_SIZE", :integer, 10)

  # The secret key base is used to sign/encrypt cookies and other secrets.
  secret_key_base =
    case env!("SECRET_KEY_BASE", :string!, nil) do
      value when is_binary(value) ->
        value

      _ ->
        case env!("SECRET_KEY_BASE_FILE", :string!, nil) do
          file when is_binary(file) ->
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
    end

  host_raw = env!("PHX_HOST", :string!)
  {host, host_port} = parse_phx_host.(host_raw)
  scheme = env!("SCHEME", :string!, "https")
  # Prefer explicit PORT; fall back to port embedded in PHX_HOST for callbacks only.
  _ = host_port
  callback_url = "#{scheme}://#{public_host.(host, host_port, scheme)}/auth/discord/callback"

  # Configure endpoint first
  config :soundboard, SoundboardWeb.Endpoint,
    # In prod, PHX_HOST represents the externally visible host. Do not append
    # the app's internal listen port unless the host itself already includes one.
    url: [
      scheme: scheme,
      host: host,
      port: nil
    ],
    http: [
      ip: {0, 0, 0, 0},
      port: port
    ],
    static_url: [
      host: host,
      port: nil
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
    client_id: env!("DISCORD_CLIENT_ID", :string!),
    client_secret: env!("DISCORD_CLIENT_SECRET", :string!),
    redirect_uri: callback_url

  # Configure Discord bot token
  discord_token = env!("DISCORD_TOKEN", :string!)

  # Store token for application use (bot will fetch it from here)
  voice_rtp_probe = env!("VOICE_RTP_PROBE", :boolean, false)
  voice_rtp_probe_timeout_ms = env!("VOICE_RTP_PROBE_TIMEOUT_MS", :integer, 6_000)
  eda_dave = env!("EDA_DAVE", :boolean, true)

  ffmpeg_available = not is_nil(System.find_executable("ffmpeg"))

  unless ffmpeg_available do
    IO.warn(
      "ffmpeg not found in PATH. Voice playback features will be unavailable until ffmpeg is installed."
    )
  end

  required_guild_id = env!("DISCORD_REQUIRED_GUILD_ID", :string, nil)

  required_role_ids =
    "DISCORD_REQUIRED_ROLE_IDS"
    |> env!(:string, "")
    |> String.split(",", trim: true)

  role_recheck_interval_seconds = env!("DISCORD_ROLE_RECHECK_INTERVAL_SECONDS", :integer, 900)

  ytdlp_executable =
    case env!("YTDLP_PATH", :string, nil) do
      path when is_binary(path) and path != "" -> path
      _ -> :system
    end

  # Writable even when the container rootfs is read-only (db volume).
  ytdlp_managed_path =
    case env!("YTDLP_PATH", :string, nil) do
      path when is_binary(path) and path != "" -> path
      _ -> "/app/priv/db/bin/yt-dlp"
    end

  # Keep uploaded cookies on the persistent, writable database volume. The
  # compiled application directory is read-only in the production container.
  youtube_cookies_path =
    env!("YOUTUBE_COOKIES_PATH", :string, "/app/priv/db/youtube/cookies.txt")

  config :soundboard,
    discord_token: discord_token,
    voice_rtp_probe: voice_rtp_probe,
    voice_rtp_probe_timeout_ms: voice_rtp_probe_timeout_ms,
    ffmpeg_available: ffmpeg_available,
    required_guild_id: required_guild_id,
    required_role_ids: required_role_ids,
    role_recheck_interval_seconds: role_recheck_interval_seconds,
    ytdlp_executable: ytdlp_executable,
    ytdlp_managed_path: ytdlp_managed_path,
    ytdlp_auto_download: true,
    youtube_cookies_path: youtube_cookies_path

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
