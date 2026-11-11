defmodule SoundboardWeb.Router do
  @moduledoc """
  Routes. The app pages (Sounds, Stats, Favorites, Settings) need an active
  subscription on hosted deployments (`:app_access`); self-hosted is always
  unlocked. Setup pages (pick a guild, claim a subdomain, subscribe) stay
  reachable while locked, since they are the way to unlock it; `:auth` only
  tells the navbar whether to show the app's links.

  Controller-rendered pages get the `@current_path` and `@presences` the app
  layout reads from `assign_controller_defaults/2`; LiveViews assign their own.

  Billing routes are compiled in unless `:enable_billing` is false, and
  `:require_stripe` 404s them whenever `STRIPE_SECRET_KEY` is unset. The
  Stripe webhook is public: its signature header is the credential, and it
  carries no CSRF token.

  `/g/:slug` scopes the app to the tenant with that slug; a signed-out
  visitor keeps the slug across sign-in (`:pending_slug`).
  """
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
    plug SoundboardWeb.Plugs.AppGate, :assign_only
  end

  pipeline :app_access do
    plug SoundboardWeb.Plugs.AppGate
  end

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

  pipeline :stripe_webhook do
    plug :accepts, ["json"]
  end

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
      post "/change", BillingController, :change
      post "/cancel", BillingController, :cancel
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

  scope "/auth", SoundboardWeb do
    pipe_through [:browser]

    if Application.compile_env(:soundboard, :enable_test_login, false) do
      get "/test-login", AuthController, :test_login
    end

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
  end

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
  end

  scope "/", SoundboardWeb do
    pipe_through([
      :browser,
      :auth,
      :ensure_authenticated_user,
      :require_role_check,
      :require_browser_basic_auth
    ])

    get "/guilds", GuildController, :index
    post "/guilds/switch", GuildController, :switch
    post "/guilds/claim", GuildController, :claim
    get "/onboarding", OnboardingController, :show
  end

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

  scope "/api", SoundboardWeb.API do
    pipe_through :api

    get "/sounds", SoundController, :index
    get "/favorites", SoundController, :favorites
    post "/sounds", SoundController, :create
    post "/sounds/:id/play", SoundController, :play
    get "/sounds/:id/file", SoundController, :file
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
    put_resp_cookie(conn, "_soundboard_key", "",
      max_age: 86_400 * 30,
      same_site: "Lax",
      secure: Application.get_env(:soundboard, :env) == :prod,
      http_only: true,
      path: "/"
    )
  end
end
