defmodule Soundboard.Accounts do
  @moduledoc """
  Aggregates account-level helpers, including edition-aware plan enforcement
  and billing metadata updates.
  """
  import Ecto.Query, only: [from: 2]

  alias Soundboard.Accounts.{Guild, Tenant, Tenants, User}
  alias Soundboard.Repo
  alias Soundboard.Sound

  @billing_keys %{
    "plan" => :plan,
    "billing_customer_id" => :billing_customer_id,
    "billing_subscription_id" => :billing_subscription_id,
    "subscription_ends_at" => :subscription_ends_at,
    plan: :plan,
    billing_customer_id: :billing_customer_id,
    billing_subscription_id: :billing_subscription_id,
    subscription_ends_at: :subscription_ends_at
  }

  @doc """
  Returns the configured edition for the current runtime (defaults to :community).
  """
  def edition do
    Application.get_env(:soundboard, :edition, :community)
  end

  def pro?, do: edition() == :pro
  def community?, do: edition() == :community

  @doc """
  Billing features are only enabled when running the Pro edition.
  """
  def billing_enabled?, do: pro?()

  @doc """
  Returns the upgrade URL surfaced in the UI when SaaS billing is enabled.
  """
  def upgrade_url do
    billing_config() |> Keyword.get(:upgrade_url)
  end

  @doc """
  Returns a manage-subscription URL if configured. Supports optional
  placeholders like `{customer_id}` or `{subscription_id}` in the portal URL.
  """
  def manage_subscription_url(%Tenant{} = tenant) do
    case billing_config() |> Keyword.get(:portal_url) do
      nil ->
        nil

      url ->
        cond do
          String.contains?(url, "{subscription_id}") && tenant.billing_subscription_id ->
            String.replace(url, "{subscription_id}", tenant.billing_subscription_id)

          String.contains?(url, "{customer_id}") && tenant.billing_customer_id ->
            String.replace(url, "{customer_id}", tenant.billing_customer_id)

          true ->
            url
        end
    end
  end

  @doc """
  Returns usage metadata for each plan-limited resource.
  """
  def plan_usage(%Tenant{} = tenant) do
    %{
      sounds: usage_for(Sound, tenant.max_sounds, tenant.id),
      users: usage_for(User, tenant.max_users, tenant.id),
      guilds: usage_for(Guild, tenant.max_guilds, tenant.id)
    }
  end

  def can_create_sound?(%Tenant{} = tenant) do
    under_limit?(tenant.max_sounds, count_for(Sound, tenant.id))
  end

  def can_add_user?(%Tenant{} = tenant) do
    under_limit?(tenant.max_users, count_for(User, tenant.id))
  end

  def can_connect_guild?(%Tenant{} = tenant) do
    under_limit?(tenant.max_guilds, count_for(Guild, tenant.id))
  end

  @doc """
  Applies billing metadata updates from webhook payloads.
  """
  def apply_billing_update(%Tenant{} = tenant, attrs) when is_map(attrs) do
    with {:ok, normalized} <- normalize_billing_attrs(attrs) do
      Tenants.update_tenant(tenant, normalized)
    end
  end

  defp billing_config do
    Application.get_env(:soundboard, :billing, [])
  end

  defp usage_for(schema, limit, tenant_id) do
    count = count_for(schema, tenant_id)

    %{
      count: count,
      limit: limit,
      remaining: remaining(limit, count),
      at_limit?: not under_limit?(limit, count)
    }
  end

  defp count_for(schema, tenant_id) do
    schema
    |> from(where: [tenant_id: ^tenant_id])
    |> Repo.aggregate(:count, :id)
  end

  defp remaining(nil, _count), do: nil
  defp remaining(limit, count) when is_integer(limit), do: max(limit - count, 0)

  defp under_limit?(nil, _count), do: true

  defp under_limit?(limit, count) when is_integer(limit) do
    count < limit
  end

  defp normalize_billing_attrs(attrs) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn
      {_key, _value}, {:error, _} = error ->
        {:halt, error}

      {key, value}, {:ok, acc} ->
        case normalize_billing_pair(key, value) do
          :skip -> {:cont, {:ok, acc}}
          {:ok, {norm_key, norm_value}} -> {:cont, {:ok, Map.put(acc, norm_key, norm_value)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp normalize_billing_pair(key, value) when is_binary(key) do
    case Map.get(@billing_keys, key) do
      nil -> :skip
      atom_key -> normalize_billing_pair(atom_key, value)
    end
  end

  defp normalize_billing_pair(key, value)
       when key in [:plan, :billing_customer_id, :billing_subscription_id, :subscription_ends_at] do
    with {:ok, normalized_value} <- normalize_billing_value(key, value) do
      {:ok, {key, normalized_value}}
    end
  end

  defp normalize_billing_pair(_key, _value), do: :skip

  defp normalize_billing_value(:plan, value), do: normalize_plan(value)

  defp normalize_billing_value(:subscription_ends_at, value) do
    normalize_subscription_date(value)
  end

  defp normalize_billing_value(_other, value) when value in [nil, ""], do: {:ok, nil}
  defp normalize_billing_value(_other, value), do: {:ok, value}

  defp normalize_plan(nil), do: {:ok, nil}
  defp normalize_plan(plan) when plan in [:community, :pro], do: {:ok, plan}

  defp normalize_plan(plan) when is_binary(plan) do
    case plan |> String.trim() |> String.downcase() do
      "" -> {:ok, nil}
      "community" -> {:ok, :community}
      "pro" -> {:ok, :pro}
      _ -> {:error, :invalid_plan}
    end
  end

  defp normalize_plan(_), do: {:error, :invalid_plan}

  defp normalize_subscription_date(nil), do: {:ok, nil}

  defp normalize_subscription_date(%DateTime{} = dt) do
    {:ok, dt |> DateTime.truncate(:second) |> DateTime.to_naive()}
  end

  defp normalize_subscription_date(%NaiveDateTime{} = ndt) do
    {:ok, NaiveDateTime.truncate(ndt, :second)}
  end

  defp normalize_subscription_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        normalize_subscription_date(dt)

      {:error, _} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} -> normalize_subscription_date(ndt)
          {:error, _} -> {:error, :invalid_timestamp}
        end
    end
  end

  defp normalize_subscription_date(value) when is_integer(value) do
    case DateTime.from_unix(value) do
      {:ok, dt} -> normalize_subscription_date(dt)
      {:error, _} -> {:error, :invalid_timestamp}
    end
  end

  defp normalize_subscription_date(_), do: {:error, :invalid_timestamp}
end
