defmodule Soundboard.Accounts.Guilds do
  @moduledoc """
  Context helpers for associating Discord guilds to tenants.
  """
  import Ecto.Query, only: [from: 2]
  alias Soundboard.Accounts
  alias Soundboard.Accounts.{Guild, Tenant}
  alias Soundboard.Repo

  def list_guilds_for_tenant(%Tenant{id: tenant_id}), do: list_guilds_for_tenant(tenant_id)

  def list_guilds_for_tenant(tenant_id) when is_integer(tenant_id) do
    Repo.all(from g in Guild, where: g.tenant_id == ^tenant_id)
  end

  def get_tenant_for_guild(guild_id) do
    with {:ok, guild} <- fetch_guild_with_tenant(guild_id) do
      {:ok, guild.tenant}
    end
  end

  def associate_guild(%Tenant{} = tenant, guild_id) do
    with normalized when not is_nil(normalized) <- normalize_guild_id(guild_id),
         :ok <- ensure_guild_capacity(tenant, normalized) do
      attrs = %{discord_guild_id: normalized, tenant_id: tenant.id}

      %Guild{}
      |> Guild.changeset(attrs)
      |> Repo.insert(
        on_conflict: [
          set: [tenant_id: tenant.id, updated_at: current_timestamp()]
        ],
        conflict_target: :discord_guild_id
      )
    else
      nil -> {:error, :invalid}
      {:error, reason} -> {:error, reason}
    end
  end

  def remove_guild(guild_id) do
    case fetch_guild(guild_id) do
      %Guild{} = guild -> Repo.delete(guild)
      _ -> {:error, :not_found}
    end
  end

  defp fetch_guild_with_tenant(guild_id) do
    case fetch_guild(guild_id) do
      %Guild{} = guild -> {:ok, Repo.preload(guild, :tenant)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_guild(guild_id) do
    case normalize_guild_id(guild_id) do
      nil ->
        {:error, :invalid}

      normalized ->
        Repo.get_by(Guild, discord_guild_id: normalized) || {:error, :not_found}
    end
  end

  defp normalize_guild_id(nil), do: nil
  defp normalize_guild_id(id) when is_integer(id), do: Integer.to_string(id)
  defp normalize_guild_id(id) when is_binary(id), do: String.trim(id)
  defp normalize_guild_id(_), do: nil

  defp ensure_guild_capacity(%Tenant{} = tenant, guild_id) do
    case Repo.get_by(Guild, discord_guild_id: guild_id) do
      %Guild{tenant_id: existing_tenant_id} when existing_tenant_id == tenant.id -> :ok
      _ -> enforce_guild_limit(tenant)
    end
  end

  defp enforce_guild_limit(%Tenant{} = tenant) do
    if Accounts.can_connect_guild?(tenant) do
      :ok
    else
      {:error, :guild_limit}
    end
  end

  defp current_timestamp do
    NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
  end
end
