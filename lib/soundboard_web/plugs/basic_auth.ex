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

    if is_nil(username) or is_nil(password) do
      Logger.warning("Basic auth credentials not configured - skipping authentication")
      conn
    else
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
    with ["Basic " <> auth] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(auth),
         {provided_username, provided_password} <- split_credentials(decoded),
         true <- provided_username == username and provided_password == password do
      conn
    else
      _ -> unauthorized(conn)
    end
  end

  defp split_credentials(decoded) do
    case String.split(decoded, ":", parts: 2) do
      [username, password] -> {username, password}
      _ -> :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="Soundboard"))
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
