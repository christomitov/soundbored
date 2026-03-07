defmodule SoundboardWeb.Plugs.APIAuth do
  @moduledoc """
  API authentication plug.
  """
  import Plug.Conn
  alias Soundboard.Accounts.ApiTokens

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        authenticate_with_token(conn, token)

      _ ->
        unauthorized(conn)
    end
  end

  defp authenticate_with_token(conn, token) do
    case verify_db_token(token) do
      {:ok, user, api_token} ->
        conn
        |> assign(:current_user, user)
        |> assign(:api_token, api_token)

      {:error, :invalid} ->
        unauthorized(conn)

      {:error, :token_update_failed} ->
        internal_error(conn)
    end
  end

  defp unauthorized(conn, message \\ "Invalid API token") do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: message})
    |> halt()
  end

  defp internal_error(conn) do
    conn
    |> put_status(:internal_server_error)
    |> Phoenix.Controller.json(%{error: "API token verification failed"})
    |> halt()
  end

  defp verify_db_token(token), do: ApiTokens.verify_token(token)
end
