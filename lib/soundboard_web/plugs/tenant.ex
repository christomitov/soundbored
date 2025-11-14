defmodule SoundboardWeb.Plugs.Tenant do
  @moduledoc """
  Determines the current tenant for the incoming request.
  """
  import Plug.Conn
  require Logger

  alias Soundboard.Accounts
  alias Soundboard.Accounts.Tenants

  def init(opts), do: opts

  def call(%Plug.Conn{assigns: %{current_tenant: %{} = tenant}} = conn, _opts) do
    conn
    |> assign(:edition, Accounts.edition())
    |> maybe_store_tenant_session(tenant)
  end

  def call(conn, opts) do
    edition = Accounts.edition()

    tenant =
      case edition do
        :pro -> resolve_pro_tenant(conn, opts)
        _ -> Tenants.ensure_default_tenant!()
      end

    conn
    |> assign(:edition, edition)
    |> assign(:current_tenant, tenant)
    |> maybe_store_tenant_session(tenant)
  end

  defp resolve_pro_tenant(conn, _opts) do
    with nil <- slug_from_params(conn),
         nil <- host_slug(conn),
         nil <- slug_from_query(conn),
         nil <- tenant_from_session(conn) do
      log_and_default(conn, :missing)
    else
      %{} = tenant ->
        tenant

      slug ->
        slug
        |> normalize_slug()
        |> lookup_tenant(conn)
    end
  end

  defp lookup_tenant(nil, conn), do: log_and_default(conn, :invalid_slug)

  defp lookup_tenant(slug, conn) do
    case Tenants.get_tenant_by_slug(slug) do
      {:ok, tenant} ->
        tenant

      {:error, :not_found} ->
        log_and_default(conn, {:not_found, slug})
    end
  end

  defp slug_from_params(%Plug.Conn{path_params: %Plug.Conn.Unfetched{}}), do: nil

  defp slug_from_params(%Plug.Conn{path_params: params}) when is_map(params) do
    normalize_slug(params["tenant_slug"] || params["tenant"])
  end

  defp slug_from_params(_), do: nil

  defp slug_from_query(%Plug.Conn{params: %Plug.Conn.Unfetched{}}), do: nil

  defp slug_from_query(%Plug.Conn{params: %{} = params}) do
    normalize_slug(params["tenant"])
  end

  defp slug_from_query(_), do: nil

  defp host_slug(%Plug.Conn{host: host}) when is_binary(host) do
    root_host = endpoint_host()

    candidate =
      cond do
        is_nil(root_host) ->
          host

        host == root_host ->
          nil

        String.ends_with?(host, "." <> root_host) ->
          host
          |> String.replace_suffix("." <> root_host, "")

        true ->
          host
      end

    candidate
    |> take_left_segment()
    |> normalize_slug()
  end

  defp host_slug(_), do: nil

  defp tenant_from_session(conn) do
    case get_session(conn, :tenant_id) do
      nil ->
        nil

      tenant_id ->
        case Tenants.get_tenant(tenant_id) do
          {:ok, tenant} -> tenant
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end

  defp log_and_default(conn, reason) do
    Logger.warning("Tenant resolution fallback: #{inspect(reason)} for host #{conn.host}")
    Tenants.ensure_default_tenant!()
  end

  defp take_left_segment(nil), do: nil

  defp take_left_segment(host) do
    host
    |> String.split(".")
    |> List.first()
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(slug) when is_binary(slug) do
    slug = String.trim(slug) |> String.downcase()

    if slug != "" and String.match?(slug, ~r/^[a-z0-9\-]+$/) do
      slug
    else
      nil
    end
  end

  defp normalize_slug(_), do: nil

  defp endpoint_host do
    :soundboard
    |> Application.get_env(SoundboardWeb.Endpoint, [])
    |> Keyword.get(:url, [])
    |> Keyword.get(:host)
  end

  defp maybe_store_tenant_session(conn, tenant) do
    case get_session(conn, :tenant_id) do
      nil -> put_session(conn, :tenant_id, tenant.id)
      id when id == tenant.id -> conn
      _ -> put_session(conn, :tenant_id, tenant.id)
    end
  rescue
    _ -> conn
  end
end
