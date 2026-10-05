defmodule SoundboardWeb.Plugs.AppGate do
  @moduledoc """
  Gate for the soundboard app pages (Sounds, Stats, Favorites, Settings).

  Self-hosted (billing dormant) everything is unlocked — the pre-billing
  behavior is unchanged. On hosted, a signed-in user must have picked a guild
  whose tenant row carries an active subscription before they can use the app;
  otherwise they are steered to `/guilds` (pick a soundboard) or `/billing`
  (subscribe). Setup pages (/guilds, /onboarding, /billing) are never gated —
  they are the path to getting unlocked.

  Also assigns `:app_unlocked` so the navbar can hide app navigation until the
  gate opens.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias Soundboard.Billing

  def init(opts), do: opts

  @doc "Runs in :auth (assign only) and again in :app_access (gate + redirect)."
  def call(conn, :assign_only) do
    assign(conn, :app_unlocked, unlocked?(conn))
  end

  def call(conn, _opts) do
    conn = assign(conn, :app_unlocked, unlocked?(conn))

    if conn.assigns.app_unlocked do
      conn
    else
      redirect_to =
        if get_session(conn, :guild_id),
          do: "/billing",
          else: "/guilds"

      conn
      |> put_flash(
        :error,
        if(redirect_to == "/billing",
          do: "That soundboard needs an active subscription",
          else: "Pick a soundboard to continue"
        )
      )
      |> redirect(to: redirect_to)
      |> halt()
    end
  end

  defp unlocked?(conn) do
    if Billing.configured?() do
      case get_session(conn, :guild_id) do
        nil -> false
        guild_id -> Billing.subscription_active?(guild_id)
      end
    else
      true
    end
  end
end
