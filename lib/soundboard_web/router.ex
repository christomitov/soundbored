defmodule SoundboardWeb.Router do
  use SoundboardWeb, :router
  require Logger

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
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
    plug SoundboardWeb.Plugs.APIAuth
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
    # Only apply basic auth in non-test environments
    if Mix.env() == :test do
      pipe_through [:browser, :auth, :ensure_authenticated_user]
    else
      pipe_through [:browser, :auth, :ensure_authenticated_user, :require_basic_auth]
    end

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
  scope "/api", SoundboardWeb.Api do
    pipe_through :api

    get "/sounds", SoundController, :index
    post "/sounds/:id/play", SoundController, :play
    post "/sounds/stop", SoundController, :stop
    
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
