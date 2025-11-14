defmodule SoundboardWeb.Plugs.APIAuth do
  @moduledoc """
  API authentication plug.
  """
  import Plug.Conn
  require Logger
  alias Soundboard.Accounts.{ApiTokens, Tenants}

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
    # First honor legacy env token for tests/backward compatibility
    if token == System.get_env("API_TOKEN") do
      Logger.warning("API using legacy env token. Migrate to user tokens.")
      assign(conn, :current_tenant, Tenants.ensure_default_tenant!())
    else
      case verify_db_token(token) do
        {:ok, user, api_token} ->
          tenant = api_token.tenant || user.tenant

          conn
          |> assign(:current_user, user)
          |> assign(:api_token, api_token)
          |> assign(:current_tenant, tenant)

        _ ->
          unauthorized(conn)
      end
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "Invalid API token"})
    |> halt()
  end

  defp verify_db_token(token), do: ApiTokens.verify_token(token)
end
