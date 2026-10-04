defmodule SoundboardWeb.Router do
  use SoundboardWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SoundboardWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_browser_basic_auth do
    plug SoundboardWeb.Plugs.BasicAuth
  end

  pipeline :require_role_check do
    plug SoundboardWeb.Plugs.RoleCheck
  end

  pipeline :auth do
    plug :fetch_session
    plug :fetch_current_user
    plug SoundboardWeb.Plugs.Tenant
    plug :assign_controller_defaults
  end

  # The shared app layout reads @current_path and @presences. LiveViews assign
  # these on the socket, but controller-rendered pages render from conn, so the
  # pipeline supplies the defaults here.
  def assign_controller_defaults(conn, _opts) do
    conn
    |> Plug.Conn.assign(:current_path, conn.request_path)
    |> Plug.Conn.assign(:presences, [])
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
    plug SoundboardWeb.Plugs.APIAuth
    plug SoundboardWeb.Plugs.Tenant
  end

  # Stripe webhook: public (no session auth) - the Stripe signature header is
  # the credential. No CSRF token is expected on this POST.
  pipeline :stripe_webhook do
    plug :accepts, ["json"]
  end

  # Billing routes are mounted unless billing is explicitly disabled via the
  # compile-time :enable_billing kill switch; the :require_stripe plug then
  # 404s them at runtime whenever STRIPE_SECRET_KEY is unset, so an
  # unconfigured deployment behaves as if the routes do not exist.
  if Application.compile_env(:soundboard, :enable_billing, true) do
    scope "/billing", SoundboardWeb do
      pipe_through([
        :browser,
        :auth,
        :ensure_authenticated_user,
        :require_role_check,
        :require_browser_basic_auth,
        :require_stripe
      ])

      get "/", BillingController, :index
      post "/checkout", BillingController, :checkout
      post "/portal", BillingController, :portal
    end

    scope "/billing", SoundboardWeb do
      pipe_through [:stripe_webhook]

      post "/webhook", BillingController, :webhook
    end
  end

  def require_stripe(conn, _opts) do
    if Soundboard.Billing.configured?() do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(:not_found, "Not Found")
      |> halt()
    end
  end

  # Discord OAuth routes - must come before protected routes
  scope "/auth", SoundboardWeb do
    pipe_through [:browser]

    if Application.compile_env(:soundboard, :enable_test_login, false) do
      get "/test-login", AuthController, :test_login
    end

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
  end

  # Protected routes
  scope "/", SoundboardWeb do
    pipe_through [
      :browser,
      :auth,
      :ensure_authenticated_user,
      :require_role_check,
      :require_browser_basic_auth
    ]

    live "/", SoundboardLive
    live "/stats", StatsLive
    live "/favorites", FavoritesLive
    live "/settings", SettingsLive

    get "/guilds", GuildController, :index
    post "/guilds/switch", GuildController, :switch
    post "/guilds/claim", GuildController, :claim
    get "/onboarding", OnboardingController, :show
  end

  # Slug entry point: /g/:slug resolves the tenant by slug and scopes the app
  # to it. Signed-out visitors keep the desired slug across the auth redirect
  # via the :pending_slug session key (see remember_pending_slug/2 below).
  scope "/g", SoundboardWeb do
    pipe_through([
      :browser,
      :auth,
      :remember_pending_slug,
      :ensure_authenticated_user,
      :require_role_check,
      :require_browser_basic_auth
    ])

    get "/:slug", GuildController, :show
  end

  scope "/uploads" do
    pipe_through [
      :browser,
      :auth,
      :ensure_authenticated_user,
      :require_role_check,
      :require_browser_basic_auth
    ]

    get "/*path", SoundboardWeb.UploadController, :show
  end

  if Mix.env() == :test do
    scope "/debug", SoundboardWeb do
      pipe_through [:browser]

      get "/session", AuthController, :debug_session
    end
  end

  # Add this new scope for API routes before your other scopes
  scope "/api", SoundboardWeb.API do
    pipe_through :api

    get "/sounds", SoundController, :index
    post "/sounds", SoundController, :create
    post "/sounds/:id/play", SoundController, :play
    post "/sounds/stop", SoundController, :stop
  end

  def fetch_current_user(conn, _) do
    user_id = get_session(conn, :user_id)

    if user_id do
      case Soundboard.Accounts.get_user(user_id) do
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

  def remember_pending_slug(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      case conn.path_info do
        ["g", slug | _] -> put_session(conn, :pending_slug, slug)
        _ -> conn
      end
    end
  end

  def ensure_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
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
