defmodule SoundboardWeb.BillingWebTest do
  @moduledoc """
  Billing over HTTP, through the endpoint and router: the Stripe webhook
  (raw-body signature check, idempotency), the billing page, and the owner's
  checkout, portal, plan change and cancel. Only Stripe's modules and the
  Discord cache are mocked; state is seeded with signed webhooks.
  """

  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.{Billing, Tenants}

  @guild "bill-guild"

  setup_with_mocks([{EDA.Cache, [:passthrough], fetch_member: fn _, _ -> {:ok, %{}} end}]) do
    :ok
  end

  setup do
    enable_billing()
    owner = user_fixture()
    {:ok, _} = Tenants.get_or_create_guild(@guild, %{owner_discord_id: owner.discord_id})
    %{owner: owner}
  end

  describe "POST /billing/webhook" do
    test "a signed event is applied once and acknowledged twice" do
      event = checkout_event("evt_web_1", @guild, "price_studio_m", "cus_web")

      assert %{"received" => true, "event" => "evt_web_1"} =
               json_response(deliver_stripe_event(event), 200)

      assert %{"event" => "duplicate"} = json_response(deliver_stripe_event(event), 200)
      assert Tenants.get_guild(@guild).max_storage_bytes == Billing.plan_cap("price_studio_m")
    end

    test "a signature over different bytes is rejected with 400", %{conn: conn} do
      payload = Jason.encode!(checkout_event("evt_web_2", @guild, "price_studio_m", "cus_web"))
      other = Jason.encode!(checkout_event("evt_web_2", @guild, "price_pro_m", "cus_web"))

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", stripe_signature(other))
        |> post("/billing/webhook", payload)

      assert json_response(conn, 400) == %{"error" => ":invalid_signature"}
      assert Tenants.get_guild(@guild).max_storage_bytes == nil
    end

    test "malformed JSON is a 400 and changes nothing", %{conn: conn} do
      assert_error_sent 400, fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", stripe_signature("{"))
        |> post("/billing/webhook", "{")
      end

      assert Tenants.get_guild(@guild).max_storage_bytes == nil
    end
  end

  describe "GET /billing" do
    test "is a 404 when Stripe is not configured", %{conn: conn, owner: owner} do
      Application.put_env(:soundboard, Billing, [])

      assert conn |> sign_in(owner, %{guild_id: @guild}) |> get("/billing") |> response(404)
    end

    test "offers the plans to a guild without a subscription", %{conn: conn, owner: owner} do
      with_mock Stripe.Subscription, list: fn _, _ -> {:ok, %Stripe.List{data: []}} end do
        html =
          conn |> sign_in(owner, %{guild_id: @guild}) |> get("/billing") |> html_response(200)

        assert html =~ "Pick a plan"
        assert html =~ "$3.99"
        assert html =~ "$9.99"
        refute html =~ "Cancel subscription"
      end
    end

    test "shows the current plan and cancel once a subscription is known", %{
      conn: conn,
      owner: owner
    } do
      deliver_stripe_event(sub_event("evt_page_sub", @guild, "price_pro_m", "si_1"))

      html = conn |> sign_in(owner, %{guild_id: @guild}) |> get("/billing") |> html_response(200)

      assert html =~ "Current plan"
      assert html =~ "Your plan"
      assert html =~ "Cancel subscription"
    end
  end

  describe "POST /billing/checkout" do
    test "sends the owner to Stripe with the guild in the session metadata", %{
      conn: conn,
      owner: owner
    } do
      with_mock Stripe.Checkout.Session, create: &checkout_session/2 do
        conn =
          conn
          |> sign_in(owner, %{guild_id: @guild})
          |> post("https://www.example.com:8443/billing/checkout", %{"price_id" => "price_pro_m"})

        assert redirected_to(conn) == "https://checkout.stripe.com/test"
        assert_received {:stripe_checkout_params, params}
        assert params.mode == :subscription
        assert params.client_reference_id == @guild
        assert params.metadata["guild_id"] == @guild
        assert params.metadata["price_id"] == "price_pro_m"
        assert params.metadata["owner_discord_id"] == owner.discord_id
        assert params.subscription_data.metadata["guild_id"] == @guild
        assert [%{price: "price_pro_m", quantity: 1}] = params.line_items
        assert params.success_url == "https://www.example.com:8443/guilds"
        assert params.cancel_url == "https://www.example.com:8443/guilds"
      end
    end

    test "checks out the unpaid guild a switch was gated on", %{conn: conn, owner: owner} do
      with_mocks([
        {EDA.Cache, [:passthrough],
         get_guild: fn _ -> %{"id" => "new-guild", "name" => "New"} end,
         fetch_member: fn _, _ -> {:ok, %{}} end},
        {Stripe.Checkout.Session, [], create: &checkout_session/2}
      ]) do
        switched =
          conn
          |> sign_in(owner, %{guild_id: @guild})
          |> post("/guilds/switch", %{"discord_guild_id" => "new-guild"})

        assert redirected_to(switched) == "/billing"

        conn =
          switched
          |> recycle()
          |> post("/billing/checkout", %{"price_id" => "price_studio_y"})

        assert redirected_to(conn) == "https://checkout.stripe.com/test"
        assert_received {:stripe_checkout_params, %{client_reference_id: "new-guild"}}
        assert get_session(conn, :billing_guild_id) == nil
      end
    end

    test "without a picked soundboard asks for one before Stripe", %{conn: conn, owner: owner} do
      with_mock Stripe.Checkout.Session,
        create: fn _, _ -> flunk("Stripe must not be called") end do
        conn = conn |> sign_in(owner) |> post("/billing/checkout", %{"price_id" => "price_pro_m"})

        assert redirected_to(conn) == "/guilds"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Pick a soundboard first"
      end
    end

    test "returns to /billing when Stripe fails or gives no URL", %{conn: conn, owner: owner} do
      for {result, flash} <- [
            {{:error, :stripe_down}, "Could not start checkout: :stripe_down"},
            {{:ok, %{id: "cs_1", url: nil}}, "Checkout session did not return a URL"}
          ] do
        with_mock Stripe.Checkout.Session, create: fn _, _ -> result end do
          conn =
            conn
            |> sign_in(owner, %{guild_id: @guild})
            |> post("/billing/checkout", %{"price_id" => "price_pro_m"})

          assert redirected_to(conn) == "/billing"
          assert Phoenix.Flash.get(conn.assigns.flash, :error) == flash
        end
      end
    end
  end

  describe "POST /billing/portal" do
    test "opens the Stripe portal for the guild's customer", %{conn: conn, owner: owner} do
      deliver_stripe_event(checkout_event("evt_portal", @guild, "price_pro_m", "cus_portal"))

      with_mock Stripe.BillingPortal.Session,
        create: fn params, _ ->
          send(self(), {:portal_params, params})
          {:ok, %{url: "https://billing.stripe.com/session"}}
        end do
        conn = conn |> sign_in(owner, %{guild_id: @guild}) |> post("/billing/portal")

        assert redirected_to(conn) == "https://billing.stripe.com/session"
        assert_received {:portal_params, %{customer: "cus_portal"}}
      end
    end

    test "says so when the guild has no Stripe customer yet", %{conn: conn, owner: owner} do
      conn = conn |> sign_in(owner, %{guild_id: @guild}) |> post("/billing/portal")

      assert redirected_to(conn) == "/billing"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Could not open billing portal: :no_customer"
    end
  end

  describe "POST /billing/change" do
    test "moves the subscription item to the new price", %{conn: conn, owner: owner} do
      deliver_stripe_event(sub_event("evt_change_sub", @guild, "price_pro_m", "si_change"))

      with_mock Stripe.SubscriptionItem,
        update: fn item_id, params, _ ->
          send(self(), {:item_update, item_id, params})
          {:ok, %{}}
        end do
        conn =
          conn
          |> sign_in(owner, %{guild_id: @guild})
          |> post("/billing/change", %{"price_id" => "price_studio_y"})

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your plan has been updated"

        assert_received {:item_update, "si_change",
                         %{price: "price_studio_y", proration_behavior: :create_prorations}}
      end
    end

    test "says so when Stripe has no active subscription", %{conn: conn, owner: owner} do
      with_mock Stripe.Subscription, list: fn _, _ -> {:ok, %Stripe.List{data: []}} end do
        conn =
          conn
          |> sign_in(owner, %{guild_id: @guild})
          |> post("/billing/change", %{"price_id" => "price_studio_y"})

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No active subscription found"
      end
    end

    test "asks for a plan when the price is missing or unknown", %{conn: conn, owner: owner} do
      for params <- [%{"price_id" => "price_bogus"}, %{}] do
        conn = conn |> sign_in(owner, %{guild_id: @guild}) |> post("/billing/change", params)

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Pick a plan first"
      end
    end
  end

  describe "POST /billing/cancel" do
    test "cancels at period end and says until when", %{conn: conn, owner: owner} do
      deliver_stripe_event(sub_event("evt_cancel_sub", @guild, "price_pro_m", "si_cancel"))
      period_end = ~U[2031-05-17 12:00:00Z]

      with_mock Stripe.Subscription,
        update: fn id, params, _ ->
          send(self(), {:sub_update, id, params})

          {:ok,
           %Stripe.Subscription{
             id: id,
             cancel_at: nil,
             items: %Stripe.List{
               data: [%Stripe.SubscriptionItem{current_period_end: DateTime.to_unix(period_end)}]
             }
           }}
        end do
        conn = conn |> sign_in(owner, %{guild_id: @guild}) |> post("/billing/cancel")

        assert redirected_to(conn) == "/billing"

        assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
                 "Your subscription will end on 2031-05-17. You keep your plan until then."

        assert_received {:sub_update, "sub_evt_cancel_sub", %{cancel_at_period_end: true}}
      end
    end

    test "says so when Stripe has no active subscription", %{conn: conn, owner: owner} do
      with_mock Stripe.Subscription, list: fn _, _ -> {:ok, %Stripe.List{data: []}} end do
        conn = conn |> sign_in(owner, %{guild_id: @guild}) |> post("/billing/cancel")

        assert redirected_to(conn) == "/billing"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                 "No active subscription found to cancel"
      end
    end
  end

  test "a member who is not the owner cannot run the guild's billing", %{conn: conn} do
    member = user_fixture()
    refuse = fn _, _ -> flunk("Stripe must not be called") end
    refuse3 = fn _, _, _ -> flunk("Stripe must not be called") end

    with_mocks([
      {Stripe.Subscription, [], list: refuse, update: refuse3},
      {Stripe.SubscriptionItem, [], update: refuse3},
      {Stripe.BillingPortal.Session, [], create: refuse},
      {Stripe.Checkout.Session, [], create: refuse}
    ]) do
      for {path, params} <- [
            {"/billing/cancel", %{}},
            {"/billing/change", %{"price_id" => "price_studio_m"}},
            {"/billing/portal", %{}},
            {"/billing/checkout", %{"price_id" => "price_studio_m"}}
          ] do
        conn = conn |> sign_in(member, %{guild_id: @guild}) |> post(path, params)

        assert redirected_to(conn) == "/billing", path

        assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                 "Only the soundboard's owner can manage its billing"
      end
    end
  end

  defp checkout_session(params, _opts) do
    send(self(), {:stripe_checkout_params, params})
    {:ok, %{id: "cs_test", url: "https://checkout.stripe.com/test"}}
  end

  defp checkout_event(id, guild_id, price_id, customer_id) do
    %{
      "id" => id,
      "type" => "checkout.session.completed",
      "data" => %{
        "object" => %{
          "client_reference_id" => guild_id,
          "customer" => customer_id,
          "metadata" => %{"guild_id" => guild_id, "price_id" => price_id}
        }
      }
    }
  end

  defp sub_event(id, guild_id, price_id, item_id) do
    %{
      "id" => id,
      "type" => "customer.subscription.updated",
      "data" => %{
        "object" => %{
          "id" => "sub_#{id}",
          "status" => "active",
          "metadata" => %{"guild_id" => guild_id},
          "items" => %{"data" => [%{"id" => item_id, "price" => %{"id" => price_id}}]}
        }
      }
    }
  end
end
