defmodule SoundboardWeb.Plugs.AppGate do
  @moduledoc """
  Gate for the soundboard app pages (Sounds, Stats, Favorites, Settings).

  Self-hosted (billing dormant) everything is unlocked — the pre-billing
  behavior is unchanged. On hosted, a signed-in user must have picked a guild
  whose tenant row carries an active subscription before they can use the app;
  otherwise they are steered to `/guilds` (pick a soundboard) or `/billing`
  (subscribe). Setup pages (/guilds, /onboarding, /billing) are never gated —
  they are the path to getting unlocked.

  Runs after `SoundboardWeb.Plugs.Tenant`, so the guild is the resolved
  `:current_guild_id`; a picked soundboard is one with a tenant row
  (`:current_guild` is a `Soundboard.Tenants.Guild`).

  Also assigns `:app_unlocked` so the navbar can hide app navigation until the
  gate opens.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias Soundboard.Billing
  alias Soundboard.Tenants.Guild

  def init(opts), do: opts

  @doc "Runs in :auth (assign only) and again in :app_access (gate + redirect)."
  def call(conn, :assign_only) do
    assign(conn, :app_unlocked, unlocked?(conn))
  end

  def call(conn, _opts) do
    conn = assign(conn, :app_unlocked, unlocked?(conn))

    cond do
      conn.assigns.app_unlocked ->
        conn

      match?(%Guild{}, conn.assigns[:current_guild]) ->
        lock(conn, "/billing", "That soundboard needs an active subscription")

      true ->
        lock(conn, "/guilds", "Pick a soundboard to continue")
    end
  end

  defp lock(conn, path, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: path)
    |> halt()
  end

  defp unlocked?(conn) do
    not Billing.configured?() or Billing.subscription_active?(conn.assigns[:current_guild_id])
  end
end
