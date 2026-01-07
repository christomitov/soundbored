defmodule SoundboardWeb.Router do
  use SoundboardWeb, :router
  require Logger
  alias Soundboard.Accounts.{ApiTokens, Tenants, User}
  alias Soundboard.Repo

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug SoundboardWeb.Plugs.Tenant
    plug :fetch_live_flash
    plug :put_root_layout, html: {SoundboardWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_basic_auth do
    plug SoundboardWeb.Plugs.BasicAuth
  end

  pipeline :auth do
    plug :fetch_session
    plug :fetch_current_user
  end

  pipeline :auth_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_session_opts
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug SoundboardWeb.Plugs.Tenant
    plug SoundboardWeb.Plugs.APIAuth
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    plug SoundboardWeb.Plugs.BasicAuth
  end

  # Discord OAuth routes - must come before protected routes
  scope "/auth", SoundboardWeb do
    pipe_through [:browser]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
  end

  # Protected routes
  scope "/", SoundboardWeb do
    pipe_through [:browser, :require_basic_auth, :auth, :ensure_authenticated_user]

    live "/", SoundboardLive
    live "/stats", StatsLive
    live "/favorites", FavoritesLive
    live "/settings", SettingsLive
  end

  # Public uploads route
  scope "/uploads" do
    pipe_through :browser

    get "/*path", SoundboardWeb.UploadController, :show
  end

  # Debug route
  scope "/debug", SoundboardWeb do
    pipe_through [:browser]

    get "/session", AuthController, :debug_session
  end

  # Add this new scope for API routes before your other scopes
  scope "/api", SoundboardWeb.API do
    pipe_through :api

    get "/sounds", SoundController, :index
    post "/sounds/:id/play", SoundController, :play
    post "/sounds/play-stream", SoundController, :play_stream
    post "/sounds/stop", SoundController, :stop

  end

  scope "/webhooks", SoundboardWeb do
    pipe_through :webhook

    post "/billing", BillingWebhookController, :create
  end

  def fetch_current_user(conn, _) do
    tenant = conn.assigns[:current_tenant] || Tenants.ensure_default_tenant!()

    conn =
      case user_from_session(conn, tenant) do
        {:ok, conn_with_user} -> conn_with_user
        {:error, conn_without_user} -> conn_without_user
      end

    if conn.assigns[:current_user] do
      conn
    else
      maybe_authenticate_with_api_token(conn, tenant)
    end
  end

  def ensure_authenticated_user(conn, _opts) do
    Logger.debug("Checking authentication. Current user: #{inspect(conn.assigns[:current_user])}")
    Logger.debug("Session: #{inspect(get_session(conn))}")

    cond do
      conn.assigns[:current_user] ->
        Logger.debug("User authenticated")
        conn

      community_passthrough?(conn) ->
        Logger.debug("Community edition access granted without OAuth")
        conn

      true ->
        Logger.debug("User not authenticated, redirecting to Discord")

        conn
        |> put_session(:return_to, conn.request_path)
        |> redirect(to: "/auth/discord")
        |> halt()
    end
  end

  defp user_from_session(conn, tenant) do
    case get_session(conn, :user_id) do
      nil ->
        {:error, assign(conn, :current_user, nil)}

      user_id ->
        case Repo.get_by(User, id: user_id, tenant_id: tenant.id) do
          nil ->
            {:error,
             conn
             |> clear_session()
             |> assign(:current_user, nil)}

          user ->
            {:ok, assign(conn, :current_user, user)}
        end
    end
  end

  defp maybe_authenticate_with_api_token(
         %Plug.Conn{assigns: %{edition: :community}} = conn,
         tenant
       ) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        authenticate_api_token(conn, token, tenant)

      _ ->
        assign(conn, :current_user, nil)
    end
  end

  defp maybe_authenticate_with_api_token(conn, _tenant) do
    assign(conn, :current_user, nil)
  end

  defp authenticate_api_token(conn, token, tenant) do
    if token == System.get_env("API_TOKEN") do
      tenant = tenant || Tenants.ensure_default_tenant!()

      conn
      |> assign(:api_token, :legacy)
      |> assign(:current_tenant, tenant)
      |> put_session(:tenant_id, tenant.id)
      |> assign(:current_user, nil)
    else
      case ApiTokens.verify_token(token) do
        {:ok, user, api_token} ->
          tenant = api_token.tenant || user.tenant || tenant || Tenants.ensure_default_tenant!()

          conn
          |> assign(:api_token, api_token)
          |> assign(:current_user, user)
          |> assign(:current_tenant, tenant)
          |> put_session(:user_id, user.id)
          |> put_session(:tenant_id, tenant.id)

        _ ->
          assign(conn, :current_user, nil)
      end
    end
  end

  defp community_passthrough?(%Plug.Conn{assigns: %{edition: :community}} = conn) do
    # Only allow bypass when an API token authenticated the request; basic auth alone
    # should still redirect users to Discord to establish a session.
    conn.assigns[:api_token]
  end

  defp community_passthrough?(_), do: false

  defp put_session_opts(conn, _opts) do
    conn
    |> put_resp_cookie("_soundboard_key", "",
      max_age: 86_400 * 30,
      same_site: "Lax",
      secure: Application.get_env(:soundboard, :env) == :prod,
      http_only: true,
      path: "/"
    )
  end
end
