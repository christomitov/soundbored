defmodule SoundboardWeb.Plugs.BasicAuth do
  @moduledoc """
  Basic authentication plug.
  """
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    username = credential("BASIC_AUTH_USERNAME")
    password = credential("BASIC_AUTH_PASSWORD")

    cond do
      bearer_header?(conn) ->
        # Allow API/Bearer auth to flow through without Basic auth challenge
        conn

      is_nil(username) or is_nil(password) ->
        # Skip basic auth if credentials are blank or missing
        Logger.info("Basic auth credentials not configured - skipping authentication")
        conn

      true ->
        Logger.info("Basic auth enabled with configured credentials")
        authenticate(conn, username, password)
    end
  end

  defp credential(key) do
    case System.get_env(key) do
      nil ->
        nil

      value when is_binary(value) ->
        if String.trim(value) == "" do
          nil
        else
          value
        end
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
      assign(conn, :basic_auth_authenticated, true)
    else
      _ -> unauthorized(conn)
    end
  end

  defp bearer_header?(conn) do
    conn
    |> get_req_header("authorization")
    |> Enum.any?(&String.starts_with?(&1, "Bearer "))
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="Soundbored"))
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
