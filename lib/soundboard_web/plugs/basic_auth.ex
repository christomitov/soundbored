defmodule SoundboardWeb.Plugs.BasicAuth do
  @moduledoc """
  Basic authentication plug.
  """
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    username = System.get_env("BASIC_AUTH_USERNAME")
    password = System.get_env("BASIC_AUTH_PASSWORD")

    if is_nil(username) or is_nil(password) do
      # Skip basic auth if credentials are not configured
      Logger.info("Basic auth credentials not configured - skipping authentication")
      conn
    else
      Logger.info("Basic auth enabled with configured credentials")
      authenticate(conn, username, password)
    end
  end

  defp authenticate(conn, username, password) do
    Logger.debug("""
    Basic Auth Debug:
    Username set: #{username}
    Auth header: #{inspect(get_req_header(conn, "authorization"))}
    """)

    with ["Basic " <> auth] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(auth),
         [^username, ^password] <- String.split(decoded, ":") do
      conn
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="Soundbored"))
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
