import Config

config :soundboard, Soundboard.Repo,
  database: "database.db",
  adapter: Ecto.Adapters.SQLite3

generate_secret_key_base = fn ->
  Base.encode64(:crypto.strong_rand_bytes(64), padding: false)
end

derive_secret_key_base = fn value ->
  :crypto.hash(:sha512, value)
  |> Base.encode64(padding: false)
end

secret_key_base =
  case System.get_env("SECRET_KEY_BASE") do
    value when is_binary(value) and byte_size(value) >= 64 ->
      value

    value when is_binary(value) ->
      derive_secret_key_base.(value)

    _ ->
      generate_secret_key_base.()
  end

config :soundboard, SoundboardWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  url: [host: "localhost", port: 4000, scheme: "http"],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: secret_key_base,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:soundboard, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:soundboard, ~w(--watch)]}
  ]

config :soundboard, SoundboardWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/soundboard_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :soundboard, dev_routes: true
config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
config :soundboard, env: :dev
