defmodule SoundboardWeb.Plugs.APIAuth do
  @moduledoc """
  API authentication plug.
  """
  import Plug.Conn
  require Logger
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
    if legacy_token?(token) do
      Logger.warning("Rejecting deprecated legacy API_TOKEN auth. Use a user API token.")
      unauthorized(conn, "Legacy API_TOKEN is no longer accepted. Use a user API token.")
    else
      case verify_db_token(token) do
        {:ok, user, api_token} ->
          conn
          |> assign(:current_user, user)
          |> assign(:api_token, api_token)

        _ ->
          unauthorized(conn)
      end
    end
  end

  defp unauthorized(conn, message \\ "Invalid API token") do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: message})
    |> halt()
  end

  defp legacy_token?(token) do
    case System.get_env("API_TOKEN") do
      legacy when is_binary(legacy) and legacy != "" -> token == legacy
      _ -> false
    end
  end

  defp verify_db_token(token), do: ApiTokens.verify_token(token)
end
