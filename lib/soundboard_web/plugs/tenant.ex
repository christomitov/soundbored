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
    |> assign(:tenant_resolution_source, conn.assigns[:tenant_resolution_source] || :preassigned)
    |> assign(:tenant_resolution_reason, conn.assigns[:tenant_resolution_reason])
    |> maybe_store_tenant_session(tenant)
  end

  def call(conn, opts) do
    edition = Accounts.edition()

    {tenant, source, reason} =
      case edition do
        :pro -> resolve_pro_tenant(conn, opts)
        _ -> {Tenants.ensure_default_tenant!(), :default, nil}
      end

    conn
    |> assign(:edition, edition)
    |> assign(:current_tenant, tenant)
    |> assign(:tenant_resolution_source, source)
    |> assign(:tenant_resolution_reason, reason)
    |> maybe_store_tenant_session(tenant)
  end

  defp resolve_pro_tenant(conn, _opts) do
    case raw_slug_from_params(conn) do
      nil ->
        case raw_slug_from_query(conn) do
          nil -> resolve_session_or_default(conn)
          slug -> resolve_slug(conn, slug, :query)
        end

      slug ->
        resolve_slug(conn, slug, :path)
    end
  end

  defp resolve_slug(conn, raw_slug, source) do
    case normalize_slug(raw_slug) do
      nil ->
        warn_and_default(conn, {:invalid_slug, raw_slug, source})

      slug ->
        case Tenants.get_tenant_by_slug(slug) do
          {:ok, tenant} ->
            {tenant, source, nil}

          {:error, :not_found} ->
            warn_and_default(conn, {:not_found, slug, source})
        end
    end
  end

  defp resolve_session_or_default(conn) do
    case tenant_from_session(conn) do
      {:ok, tenant} ->
        {tenant, :session, nil}

      {:error, reason} ->
        warn_and_default(conn, reason)
    end
  end

  defp warn_and_default(_conn, reason) do
    Logger.warning("Tenant resolution fallback: #{format_reason(reason)}")
    {Tenants.ensure_default_tenant!(), :default, reason}
  end

  defp raw_slug_from_params(%Plug.Conn{path_params: %Plug.Conn.Unfetched{}}), do: nil

  defp raw_slug_from_params(%Plug.Conn{path_params: params}) when is_map(params) do
    params["tenant_slug"] || params["tenant"]
  end

  defp raw_slug_from_params(_), do: nil

  defp raw_slug_from_query(%Plug.Conn{params: %Plug.Conn.Unfetched{}}), do: nil

  defp raw_slug_from_query(%Plug.Conn{params: %{} = params}) do
    params["tenant"]
  end

  defp raw_slug_from_query(_), do: nil

  defp tenant_from_session(conn) do
    case get_session(conn, :tenant_id) do
      nil ->
        {:error, :missing}

      tenant_id ->
        case Tenants.get_tenant(tenant_id) do
          {:ok, tenant} -> {:ok, tenant}
          _ -> {:error, {:stale_session, tenant_id}}
        end
    end
  rescue
    _ -> {:error, :missing}
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

  defp format_reason(:missing),
    do: "no tenant params or session present; using default tenant"

  defp format_reason({:invalid_slug, raw_slug, source}),
    do: "invalid #{source} tenant slug #{inspect(raw_slug)}; using default tenant"

  defp format_reason({:not_found, slug, source}),
    do: "tenant #{slug} not found from #{source}; using default tenant"

  defp format_reason({:stale_session, tenant_id}),
    do: "session tenant #{inspect(tenant_id)} missing; using default tenant"

  defp format_reason(_reason),
    do: "falling back to default tenant"

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
