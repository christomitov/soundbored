defmodule SoundboardWeb.Plugs.APIAuth do
  @moduledoc """
  API authentication plug.
  """
  import Plug.Conn
  require Logger
  alias Soundboard.Accounts
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
    edition = conn.assigns[:edition] || Accounts.edition()
    current_tenant = conn.assigns[:current_tenant]
    resolution_source = conn.assigns[:tenant_resolution_source]
    resolution_reason = conn.assigns[:tenant_resolution_reason]

    case classify_token(edition, token) do
      :legacy ->
        tenant = current_tenant || Tenants.ensure_default_tenant!()

        conn
        |> assign(:api_token, :legacy)
        |> assign(:current_tenant, tenant)
        |> assign(:tenant_resolution_source, resolution_source || :api_token)
        |> assign(:tenant_resolution_reason, nil)
        |> persist_session(tenant, nil)

      :deny ->
        unauthorized(conn)

      :db ->
        authenticate_with_db_token(
          conn,
          token,
          edition,
          current_tenant,
          resolution_source,
          resolution_reason
        )
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "Invalid API token"})
    |> halt()
  end

  defp authenticate_with_db_token(
         conn,
         token,
         edition,
         current_tenant,
         resolution_source,
         resolution_reason
       ) do
    with {:ok, user, api_token} <- verify_db_token(token),
         token_tenant <- api_token.tenant || user.tenant,
         {:ok, tenant} <-
           authorize_tenant(
             edition,
             current_tenant,
             resolution_source,
             resolution_reason,
             token_tenant
           ) do
      conn
      |> assign(:current_user, user)
      |> assign(:api_token, api_token)
      |> assign(:current_tenant, tenant)
      |> assign(:tenant_resolution_source, :api_token)
      |> assign(:tenant_resolution_reason, nil)
      |> persist_session(tenant, user)
    else
      {:error, :mismatch} ->
        conn
        |> clear_auth_session()
        |> unauthorized()

      _ ->
        unauthorized(conn)
    end
  end

  defp classify_token(edition, token) do
    legacy_token = System.get_env("API_TOKEN")

    cond do
      edition == :community and token == legacy_token -> :legacy
      token == legacy_token -> :deny
      true -> :db
    end
  end

  defp authorize_tenant(:community, current_tenant, _source, _reason, token_tenant) do
    {:ok, current_tenant || token_tenant || Tenants.ensure_default_tenant!()}
  end

  defp authorize_tenant(:pro, _current_tenant, :default, reason, token_tenant)
       when reason in [:missing, nil] do
    {:ok, token_tenant}
  end

  defp authorize_tenant(:pro, nil, _source, _reason, token_tenant), do: {:ok, token_tenant}

  defp authorize_tenant(:pro, %{} = current_tenant, _source, _reason, %{} = token_tenant) do
    if current_tenant.id == token_tenant.id do
      {:ok, token_tenant}
    else
      Logger.warning(
        "API token tenant mismatch: resolved #{inspect(current_tenant.id)}, token #{inspect(token_tenant.id)}"
      )

      {:error, :mismatch}
    end
  end

  defp authorize_tenant(:pro, _current_tenant, _source, _reason, token_tenant),
    do: {:ok, token_tenant}

  defp persist_session(conn, %{} = tenant, user) do
    conn
    |> put_session(:tenant_id, tenant.id)
    |> maybe_put_user_session(user)
  rescue
    _ -> conn
  end

  defp persist_session(conn, _tenant, _user), do: conn

  defp maybe_put_user_session(conn, %{} = user), do: put_session(conn, :user_id, user.id)
  defp maybe_put_user_session(conn, _user), do: conn

  defp clear_auth_session(conn) do
    conn
    |> clear_session()
    |> assign(:current_user, nil)
    |> assign(:api_token, nil)
  end

  defp verify_db_token(token), do: ApiTokens.verify_token(token)
end
