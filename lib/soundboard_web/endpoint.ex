defmodule SoundboardWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :soundboard

  @session_options [
    store: :cookie,
    key: "_soundboard_key",
    signing_salt: "dxNUerVp",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :soundboard,
    gzip: false,
    only: SoundboardWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :soundboard
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: Application.compile_env(:soundboard, :max_upload_bytes, 10_000_000),
    json_decoder: Phoenix.json_library(),
    body_reader: {SoundboardWeb.RawBodyReader, :read_body, []}

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SoundboardWeb.Router
end
