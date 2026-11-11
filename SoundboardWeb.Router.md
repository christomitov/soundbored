# `SoundboardWeb.Router`

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

# `api`

# `app_access`

# `assign_controller_defaults`

# `auth`

# `auth_browser`

# `browser`

# `call`

Callback invoked by Plug on every request.

# `ensure_authenticated_user`

# `fetch_current_user`

# `formatted_routes`

# `init`

Callback required by Plug that initializes the router
for serving web requests.

# `remember_pending_slug`

# `require_browser_basic_auth`

# `require_role_check`

# `require_stripe`

# `stripe_webhook`

# `verified_route?`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
