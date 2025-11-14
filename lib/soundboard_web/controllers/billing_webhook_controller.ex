defmodule SoundboardWeb.BillingWebhookController do
  use SoundboardWeb, :controller

  alias Soundboard.Accounts
  alias Soundboard.Accounts.Tenants

  def create(conn, params) do
    if Accounts.billing_enabled?() do
      with {:ok, tenant} <- fetch_tenant(params),
           {:ok, tenant} <- Accounts.apply_billing_update(tenant, params) do
        json(conn, %{data: serialize_tenant(tenant)})
      else
        {:error, :missing_tenant} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "tenant identifier is required"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "tenant not found"})

        {:error, :invalid_plan} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid plan"})

        {:error, :invalid_timestamp} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "invalid subscription timestamp"})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "validation failed", details: translate_errors(changeset)})
      end
    else
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch_tenant(%{"tenant_slug" => slug}) when is_binary(slug) do
    slug
    |> String.trim()
    |> String.downcase()
    |> Tenants.get_tenant_by_slug()
  end

  defp fetch_tenant(%{"tenant_id" => id}) do
    Tenants.get_tenant(id)
  end

  defp fetch_tenant(_), do: {:error, :missing_tenant}

  defp serialize_tenant(tenant) do
    %{
      id: tenant.id,
      slug: tenant.slug,
      plan: tenant.plan,
      billing_customer_id: tenant.billing_customer_id,
      billing_subscription_id: tenant.billing_subscription_id,
      subscription_ends_at: format_timestamp(tenant.subscription_ends_at)
    }
  end

  defp format_timestamp(nil), do: nil

  defp format_timestamp(%DateTime{} = dt) do
    dt
    |> DateTime.to_naive()
    |> format_timestamp()
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
