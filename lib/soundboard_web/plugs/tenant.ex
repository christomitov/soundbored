defmodule SoundboardWeb.Plugs.Tenant do
  @moduledoc """
  Resolves the current tenant (guild) for a request.

  Resolution order:
  1. Subdomain — `{slug}.soundbored.app` (base host configured as
     `:tenant_base_host`) must map to an existing guild slug, else 404.
  2. Session — `guild_id` set by the guild switcher.
  3. Default guild — keeps zero-config single-guild deployments unchanged.

  A signed-in user (browser session or API token) must be a member of the
  resolved guild (`Soundboard.Tenants.Membership`): a subdomain they are not
  in is a 403, and a session guild they are not in falls back to the default
  guild. Signed-out requests resolve normally; the routes that need a user
  redirect them to sign in afterwards.

  Assigns `:current_guild_id` (string) and `:current_guild` (row or nil), and
  mirrors the id into the session so LiveViews receive it on mount.
  """

  import Phoenix.Controller, only: [put_view: 2]
  import Plug.Conn, only: [get_session: 2]
  alias Plug.Conn
  alias Soundboard.Tenants
  alias Soundboard.Tenants.{Guild, Membership}

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = Plug.Conn.fetch_session(conn)

    case resolve_from_subdomain(conn) do
      {:ok, guild} ->
        if allowed?(conn, guild.discord_guild_id),
          do: assign_tenant(conn, guild),
          else: halt_with(conn, :forbidden, "You are not a member of this soundboard")

      :no_subdomain ->
        assign_default_tenant(conn)

      :unknown_subdomain ->
        halt_with(conn, :not_found, "Unknown soundboard")
    end
  end

  defp halt_with(conn, status, message) do
    conn
    |> Conn.put_status(status)
    |> put_view(SoundboardWeb.ErrorHTML)
    |> Conn.send_resp(status, message)
    |> Conn.halt()
  end

  defp resolve_from_subdomain(conn) do
    case tenant_slug(conn.host) do
      nil ->
        :no_subdomain

      slug ->
        case Tenants.get_by_slug(slug) do
          %Guild{} = guild -> {:ok, guild}
          nil -> :unknown_subdomain
        end
    end
  end

  defp tenant_slug(host) do
    case base_host() do
      nil ->
        nil

      base ->
        suffix = "." <> base

        if host != base and String.ends_with?(host, suffix) do
          host |> String.slice(0, byte_size(host) - byte_size(suffix)) |> String.downcase()
        end
    end
  end

  defp base_host, do: Application.get_env(:soundboard, :tenant_base_host, nil)

  defp assign_default_tenant(conn) do
    guild_id = get_session(conn, "guild_id")

    guild =
      case guild_id && Tenants.get_guild(guild_id) do
        %Guild{} = guild -> if allowed?(conn, guild.discord_guild_id), do: guild
        _ -> nil
      end

    resolved = guild || %{discord_guild_id: Tenants.default_guild_id(), slug: nil, name: nil}
    assign_tenant(conn, resolved)
  end

  defp allowed?(conn, guild_id) do
    case conn.assigns[:current_user] do
      %{discord_id: discord_id} -> Membership.member?(guild_id, discord_id)
      _ -> true
    end
  end

  defp assign_tenant(conn, guild) do
    guild_id = guild.discord_guild_id

    conn
    |> Conn.assign(:current_guild_id, guild_id)
    |> Conn.assign(:current_guild, guild)
    |> Conn.put_session(:guild_id, guild_id)
  end
end
