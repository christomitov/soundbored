defmodule SoundboardWeb.Live.TenantHelpers do
  @moduledoc """
  Utilities for determining the active tenant in LiveViews.
  """
  alias Soundboard.Accounts.Tenants

  def tenant_id_from_session(session, user) do
    cond do
      tenant_id = parse_tenant_id(Map.get(session, "tenant_id")) ->
        tenant_id

      user && user.tenant_id ->
        user.tenant_id

      true ->
        Tenants.ensure_default_tenant!().id
    end
  end

  defp parse_tenant_id(nil), do: nil
  defp parse_tenant_id(tenant_id) when is_integer(tenant_id), do: tenant_id

  defp parse_tenant_id(tenant_id) when is_binary(tenant_id) do
    case Integer.parse(tenant_id) do
      {parsed, _} -> parsed
      :error -> nil
    end
  end
end
