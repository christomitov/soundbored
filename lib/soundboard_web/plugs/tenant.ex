defmodule SoundboardWeb.Plugs.Tenant do
  @moduledoc """
  Resolves the current tenant (guild) for a request.

  Resolution order:
  1. Subdomain — `{slug}.soundbored.app` (base host configured as
     `:tenant_base_host`) must map to an existing guild slug, else 404.
  2. Session — `guild_id` set by the guild switcher.
  3. Default guild — keeps zero-config single-guild deployments unchanged.

  Assigns `:current_guild_id` (string) and `:current_guild` (row or nil), and
  mirrors the id into the session so LiveViews receive it on mount.
  """

  import Phoenix.Controller, only: [put_view: 2]
  import Plug.Conn, only: [get_session: 2]
  alias Plug.Conn
  alias Soundboard.Tenants

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = Plug.Conn.fetch_session(conn)

    case resolve_from_subdomain(conn) do
      {:ok, guild} ->
        assign_tenant(conn, guild)

      :no_subdomain ->
        assign_default_tenant(conn)

      :unknown_subdomain ->
        conn
        |> Conn.put_status(:not_found)
        |> put_view(SoundboardWeb.ErrorHTML)
        |> Conn.send_resp(:not_found, "Unknown soundboard")
        |> Conn.halt()
    end
  end

  defp resolve_from_subdomain(conn) do
    case tenant_slug(conn.host) do
      nil ->
        :no_subdomain

      slug ->
        case Tenants.get_by_slug(slug) do
          %Soundboard.Tenants.Guild{} = guild -> {:ok, guild}
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
        %Soundboard.Tenants.Guild{} = guild -> guild
        _ -> nil
      end

    resolved = guild || %{discord_guild_id: Tenants.default_guild_id(), slug: nil, name: nil}
    assign_tenant(conn, resolved)
  end

  defp assign_tenant(conn, guild) do
    guild_id = guild.discord_guild_id

    conn
    |> Conn.assign(:current_guild_id, guild_id)
    |> Conn.assign(:current_guild, guild)
    |> Conn.put_session(:guild_id, guild_id)
  end
end
