defmodule SoundboardWeb.BillingWebhookControllerTest do
  use SoundboardWeb.ConnCase

  alias Soundboard.Accounts.Tenants

  setup %{conn: conn} do
    original = Application.get_env(:soundboard, :edition, :community)
    Application.put_env(:soundboard, :edition, :pro)

    on_exit(fn ->
      Application.put_env(:soundboard, :edition, original)
    end)

    conn = put_req_header(conn, "content-type", "application/json")

    %{conn: conn, tenant: Tenants.ensure_default_tenant!()}
  end

  test "updates tenant billing info", %{conn: conn, tenant: tenant} do
    payload = %{
      "tenant_id" => tenant.id,
      "plan" => "pro",
      "billing_customer_id" => "cust_123",
      "billing_subscription_id" => "sub_456",
      "subscription_ends_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn = post(conn, ~p"/webhooks/billing", Jason.encode!(payload))
    assert %{"data" => data} = json_response(conn, 200)
    assert data["plan"] == "pro"

    {:ok, reloaded} = Tenants.get_tenant(tenant.id)
    assert reloaded.plan == :pro
    assert reloaded.billing_customer_id == "cust_123"
  end

  test "returns 422 when plan is invalid", %{conn: conn, tenant: tenant} do
    conn =
      post(
        conn,
        ~p"/webhooks/billing",
        Jason.encode!(%{"tenant_slug" => tenant.slug, "plan" => "invalid"})
      )

    assert %{"error" => "invalid plan"} = json_response(conn, 422)
  end

  test "no-ops when billing is disabled", %{conn: conn, tenant: tenant} do
    Application.put_env(:soundboard, :edition, :community)

    conn = post(conn, ~p"/webhooks/billing", Jason.encode!(%{"tenant_id" => tenant.id}))
    assert response(conn, 204) == ""
  end
end
