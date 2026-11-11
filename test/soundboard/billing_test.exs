defmodule Soundboard.BillingTest do
  @moduledoc """
  Unit tests for SB-3 billing: price-to-cap mapping, webhook provisioning
  (checkout.session.completed), subscription deletion zeroing the cap while
  keeping the row, and duplicate-event idempotency.
  """

  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.Billing
  alias Soundboard.Tenants

  @secret "whsec_test"
  setup do
    Application.put_env(:soundboard, Billing,
      secret_key: "sk_test_key",
      webhook_secret: @secret,
      price_pro_monthly: "price_pro_monthly",
      price_pro_yearly: "price_pro_yearly",
      price_studio_monthly: "price_studio_monthly",
      price_studio_yearly: "price_studio_yearly"
    )

    on_exit(fn -> Application.put_env(:soundboard, Billing, []) end)

    :ok
  end

  describe "plan_cap/1" do
    test "maps each configured price id to its tier cap" do
      assert Billing.plan_cap("price_pro_monthly") == 1_073_741_824
      assert Billing.plan_cap("price_pro_yearly") == 1_073_741_824
      assert Billing.plan_cap("price_studio_monthly") == 5_368_709_120
      assert Billing.plan_cap("price_studio_yearly") == 5_368_709_120
    end

    test "unknown price ids and non-binaries map to nil" do
      assert Billing.plan_cap("price_unknown") == nil
      assert Billing.plan_cap(nil) == nil
    end
  end

  describe "create_checkout_session/2" do
    test "validates the price against the configured set" do
      assert {:error, :invalid_price} = Billing.create_checkout_session("g1", "price_unknown")
      assert {:error, :invalid_price} = Billing.create_checkout_session("g1", "")
    end

    test "builds a subscription checkout carrying the guild id for reconciliation" do
      with_mock Stripe.Checkout.Session, [],
        create: fn params, _opts ->
          send(self(), {:stripe_checkout_params, params})
          {:ok, %{id: "cs_test", url: "https://checkout.stripe.com/test"}}
        end,
        create: fn params ->
          send(self(), {:stripe_checkout_params, params})
          {:ok, %{id: "cs_test", url: "https://checkout.stripe.com/test"}}
        end do
        assert {:ok, %{id: "cs_test", url: "https://checkout.stripe.com/test"}} =
                 Billing.create_checkout_session("bill-guild", "price_pro_monthly")

        assert_received {:stripe_checkout_params, params}
        assert params.client_reference_id == "bill-guild"
        assert params.mode == "subscription" || params.mode == :subscription
        assert params.metadata["guild_id"] == "bill-guild"
        assert params.metadata["price_id"] == "price_pro_monthly"
        assert params.subscription_data.metadata["guild_id"] == "bill-guild"
        assert [%{price: "price_pro_monthly", quantity: 1}] = params.line_items
        assert params.success_url =~ "/guilds"
        assert params.cancel_url =~ "/guilds"
      end
    end
  end

  describe "handle_webhook/2" do
    test "checkout.session.completed provisions the guild at the plan cap" do
      event = checkout_event("evt_checkout_1", "bill-checkout", "price_studio_monthly", "cus_1")
      {payload, header} = signed(Jason.encode!(event))

      assert {:ok, "evt_checkout_1"} = Billing.handle_webhook(payload, header)

      guild = Tenants.get_guild("bill-checkout")
      assert %Tenants.Guild{} = guild
      assert guild.max_storage_bytes == 5_368_709_120
      assert Billing.customer_id_for_guild("bill-checkout") == "cus_1"
    end

    test "what a webhook remembers outlives the process that handled it" do
      event = checkout_event("evt_outlives", "bill-outlives", "price_pro_monthly", "cus_outlives")
      {payload, header} = signed(Jason.encode!(event))

      {pid, ref} = spawn_monitor(fn -> {:ok, _} = Billing.handle_webhook(payload, header) end)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

      assert Billing.customer_id_for_guild("bill-outlives") == "cus_outlives"
      assert {:ok, :duplicate} = Billing.handle_webhook(payload, header)
    end

    test "a tampered payload is rejected with an invalid signature" do
      {payload, _header} =
        signed(Jason.encode!(checkout_event("evt_x", "g", "price_pro_monthly", "cus_x")))

      assert {:error, :invalid_signature} = Billing.handle_webhook(payload, "t=1,v1=deadbeef")
    end

    test "subscription deletion zeroes the cap but keeps the guild row" do
      {:ok, _} = Tenants.get_or_create_guild("bill-del", %{max_storage_bytes: 1_073_741_824})

      {payload, header} =
        signed(
          Jason.encode!(
            sub_event("customer.subscription.deleted", "evt_del_1", %{"guild_id" => "bill-del"})
          )
        )

      assert {:ok, "evt_del_1"} = Billing.handle_webhook(payload, header)

      guild = Tenants.get_guild("bill-del")
      assert %Tenants.Guild{} = guild
      assert guild.max_storage_bytes == 0
    end

    test "subscription updates cap the guild to the new plan" do
      {:ok, _} = Tenants.get_or_create_guild("bill-upd", %{max_storage_bytes: 1_073_741_824})

      {payload, header} =
        signed(
          Jason.encode!(
            sub_event("customer.subscription.updated", "evt_upd_1", %{
              "guild_id" => "bill-upd"
            })
          )
        )

      assert {:ok, "evt_upd_1"} = Billing.handle_webhook(payload, header)
      assert Tenants.get_guild("bill-upd").max_storage_bytes == 5_368_709_120
    end

    test "duplicate event ids are processed once (no-op on replay)" do
      {payload, header} =
        signed(
          Jason.encode!(checkout_event("evt_dup_1", "bill-dup", "price_pro_monthly", "cus_dup"))
        )

      assert {:ok, "evt_dup_1"} = Billing.handle_webhook(payload, header)
      assert {:ok, :duplicate} = Billing.handle_webhook(payload, header)

      Billing.reset_memory()
      assert {:ok, "evt_dup_1"} = Billing.handle_webhook(payload, header)
      assert Tenants.get_guild("bill-dup").max_storage_bytes == 1_073_741_824
      assert Billing.customer_id_for_guild("bill-dup") == "cus_dup"
    end
  end

  describe "subscription_active?/1" do
    test "only exact plan caps are active; legacy/default, cap 0, or no row are not" do
      refute Billing.subscription_active?("bill-none")

      {:ok, _} = Tenants.get_or_create_guild("bill-legacy")
      refute Billing.subscription_active?("bill-legacy")

      {:ok, _} = Tenants.get_or_create_guild("bill-zero", %{max_storage_bytes: 0})
      guild = Tenants.get_guild("bill-zero")
      assert guild.max_storage_bytes == 0
      refute Billing.subscription_active?("bill-zero")

      {:ok, _} =
        Tenants.get_or_create_guild("bill-paid", %{max_storage_bytes: 1_073_741_824})

      assert Billing.subscription_active?("bill-paid")
    end
  end

  defp signed(payload, secret \\ @secret) do
    ts = Integer.to_string(System.system_time(:second))
    mac = Base.encode16(:crypto.mac(:hmac, :sha256, secret, ts <> "." <> payload), case: :lower)
    {payload, "t=#{ts},v1=#{mac}"}
  end

  defp checkout_event(id, guild_id, price_id, customer_id) do
    %{
      "id" => id,
      "type" => "checkout.session.completed",
      "data" => %{
        "object" => %{
          "object" => "checkout.session",
          "client_reference_id" => guild_id,
          "customer" => customer_id,
          "metadata" => %{"guild_id" => guild_id, "price_id" => price_id}
        }
      }
    }
  end

  defp sub_event(type, id, metadata) do
    %{
      "id" => id,
      "type" => type,
      "data" => %{
        "object" => %{
          "object" => "subscription",
          "metadata" => metadata,
          "items" => %{
            "data" => [%{"price" => %{"id" => "price_studio_monthly"}}]
          }
        }
      }
    }
  end
end
