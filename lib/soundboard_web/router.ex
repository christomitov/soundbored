defmodule SoundboardWeb.Router do
  use SoundboardWeb, :router
  # Keep this import
  import Plug.BasicAuth
  import Logger

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SoundboardWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_cache_headers
    plug :force_ssl_scheme
    plug :put_url_scheme
    plug SoundboardWeb.Plugs.BasicAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Add new pipeline for API authentication
  pipeline :api_auth do
    plug :api_authentication
  end

  # Move basic auth to its own pipeline and make it first
  pipeline :auth do
    plug :basic_auth,
      username: System.get_env("BASIC_AUTH_USERNAME") || "admin",
      password: System.get_env("BASIC_AUTH_PASSWORD") || "admin"
  end

  # Remove basic auth from main_auth
  pipeline :main_auth do
    plug :fetch_session
    plug :fetch_current_user
  end

  pipeline :require_auth do
    plug :ensure_authenticated_user
  end

  # Main app routes with Discord auth
  scope "/", SoundboardWeb do
    pipe_through [:browser, :fetch_current_user, :ensure_authenticated_user]

    live "/", SoundboardLive
    live "/stats", LeaderboardLive
    live "/favorites", FavoritesLive
  end

  # Discord OAuth routes - no auth requirements
  scope "/auth", SoundboardWeb do
    pipe_through [:browser]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
  end

  # Other scopes may use custom stacks.
  # scope "/api", SoundboardWeb do
  #   pipe_through :api
  # end

  # Add this scope near your other public routes
  scope "/uploads" do
    pipe_through :browser

    get "/*path", SoundboardWeb.UploadController, :show
  end

  # Add this scope for API routes
  # scope "/api", SoundboardWeb.API do
  #   pipe_through [:api, :api_auth]

  #   get "/sounds", SoundController, :index
  #   post "/sounds/:id/play", SoundController, :play
  # end

  # Debug route
  scope "/debug", SoundboardWeb do
    pipe_through [:browser]

    get "/session", AuthController, :debug_session
  end

  def fetch_current_user(conn, _) do
    user_id = get_session(conn, :user_id)

    if user_id do
      case Soundboard.Repo.get(Soundboard.Accounts.User, user_id) do
        nil ->
          conn
          |> clear_session()
          |> assign(:current_user, nil)
        user ->
          assign(conn, :current_user, user)
      end
    else
      assign(conn, :current_user, nil)
    end
  end

  def ensure_authenticated_user(conn, _opts) do
    Logger.debug("Checking authentication. Current user: #{inspect(conn.assigns[:current_user])}")
    Logger.debug("Session: #{inspect(get_session(conn))}")

    if conn.assigns[:current_user] do
      Logger.debug("User authenticated")
      conn
    else
      Logger.debug("User not authenticated, redirecting to Discord")
      conn
      |> put_session(:return_to, conn.request_path)
      |> redirect(to: "/auth/discord")
      |> halt()
    end
  end

  # Add the authentication function
  defp api_authentication(conn, _opts) do
    api_token = System.get_env("API_TOKEN") || raise "API_TOKEN environment variable is not set"

    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token == api_token ->
        conn

      _ ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Invalid API token"})
        |> halt()
    end
  end

  defp put_cache_headers(conn, _) do
    put_resp_header(conn, "cache-control", "no-cache, no-store, must-revalidate")
  end

  defp put_url_scheme(conn, _opts) do
    scheme = System.get_env("SCHEME") || "https"
    conn = put_private(conn, :url_scheme, String.to_atom(scheme))
    conn
  end

  defp force_ssl_scheme(conn, _opts) do
    scheme = System.get_env("SCHEME") || "https"
    %{conn | scheme: String.to_atom(scheme)}
  end
end
