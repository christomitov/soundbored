defmodule SoundboardWeb.BillingWebTest do
  @moduledoc """
  Web tests for SB-3 billing: webhook signature rejection, the auth gate on
  billing routes, checkout session contents (guild id in client_reference_id
  and metadata), route dormancy when Stripe is unconfigured, and the guild
  switch paywall gate.
  """

  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias EDA.Cache
  alias Soundboard.Accounts.User
  alias Soundboard.Billing
  alias Soundboard.Repo
  alias Soundboard.Tenants

  @stripe_env [
    secret_key: "sk_test_key",
    webhook_secret: "whsec_test",
    price_pro_monthly: "price_pro_m",
    price_pro_yearly: "price_pro_y",
    price_studio_monthly: "price_studio_m",
    price_studio_yearly: "price_studio_y"
  ]

  setup do
    Billing.reset_memory()

    on_exit(fn ->
      Billing.reset_memory()
      Application.put_env(:soundboard, Billing, [])
    end)

    :ok
  end

  defp conn!(conn),
    do:
      conn
      |> init_test_session(%{})
      |> fetch_query_params()
      |> fetch_flash()
      |> Map.update!(:params, &Map.put(&1, "_format", "html"))

  defp call!(conn, action, params \\ %{}) do
    conn = Map.update!(conn, :params, &Map.merge(&1, params))
    SoundboardWeb.BillingController.call(conn, action)
  end

  defp call_guild!(conn, action, params) do
    conn = Map.update!(conn, :params, &Map.merge(&1, params))
    SoundboardWeb.GuildController.call(conn, action)
  end

  describe "POST /billing/webhook" do
    test "a bad signature is rejected with 400", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)
      payload = Jason.encode!(%{"id" => "evt_bad", "type" => "ping"})

      conn =
        conn
        |> assign(:raw_body, [payload])
        |> put_req_header(
          "stripe-signature",
          "t=#{System.system_time(:second)},v1=notthesignature"
        )
        |> call!(:webhook)

      assert response(conn, 400)
    end

    test "a valid signature with an unhandled type is accepted", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      payload =
        Jason.encode!(%{
          "id" => "evt_other",
          "type" => "customer.created",
          "data" => %{"object" => %{}}
        })

      header = webhook_header(payload)

      conn =
        conn
        |> assign(:raw_body, [payload])
        |> put_req_header("stripe-signature", header)
        |> call!(:webhook)

      assert response(conn, 200)
    end
  end

  describe "POST /billing/checkout" do
    test "the session carries the guild id in client_reference_id and metadata", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Stripe.Checkout.Session, [],
        create: fn params, _opts ->
          send(self(), {:stripe_checkout_params, params})
          {:ok, %{id: "cs_test_1", url: "https://checkout.stripe.com/test"}}
        end,
        create: fn params ->
          send(self(), {:stripe_checkout_params, params})
          {:ok, %{id: "cs_test_1", url: "https://checkout.stripe.com/test"}}
        end do
        conn =
          conn!(conn)
          |> assign(:current_user, %{discord_id: "owner-1"})
          |> assign(:current_guild_id, "checkout-guild")
          |> call!(:checkout, %{"price_id" => "price_pro_m"})

        assert redirected_to(conn) == "https://checkout.stripe.com/test"

        assert_received {:stripe_checkout_params, params}
        assert params.client_reference_id == "checkout-guild"
        assert params.mode == :subscription
        assert params.metadata["guild_id"] == "checkout-guild"
        assert params.metadata["price_id"] == "price_pro_m"
        assert params.metadata["owner_discord_id"] == "owner-1"
        assert params.subscription_data.metadata["guild_id"] == "checkout-guild"
        assert [%{price: "price_pro_m", quantity: 1}] = params.line_items
      end
    end

    test "the pending billing guild (from a gated switch) wins over the current guild", %{
      conn: conn
    } do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Stripe.Checkout.Session, [],
        create: fn params, _opts ->
          send(self(), {:stripe_checkout_params, params})
          {:ok, %{id: "cs_test_2", url: "https://checkout.stripe.com/test"}}
        end,
        create: fn params ->
          send(self(), {:stripe_checkout_params, params})
          {:ok, %{id: "cs_test_2", url: "https://checkout.stripe.com/test"}}
        end do
        conn =
          conn!(conn)
          |> put_session(:billing_guild_id, "switch-target")
          |> assign(:current_user, %{discord_id: "owner-1"})
          |> assign(:current_guild_id, "current-guild")
          |> call!(:checkout, %{"price_id" => "price_studio_y"})

        assert redirected_to(conn) == "https://checkout.stripe.com/test"

        assert_received {:stripe_checkout_params, params}
        assert params.client_reference_id == "switch-target"
      end
    end
  end

  describe "auth gating on the billing scope" do
    test "an unauthenticated request to /billing is redirected to auth", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      conn = conn |> init_test_session(%{}) |> get("/billing")

      assert redirected_to(conn) == "/auth/discord"
    end
  end

  describe "route dormancy when Stripe is unconfigured" do
    test "GET /billing is a 404 when Stripe is not configured", %{conn: conn} do
      Application.put_env(:soundboard, Billing, [])
      user = insert_user!()

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> get("/billing")

      assert response(conn, 404)
    end
  end

  describe "POST /guilds/switch paywall gate" do
    @guild %{"id" => "unpaid-guild", "name" => "Unpaid"}

    test "an unpaid guild redirects to /billing and creates no tenant row", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Cache, [],
        get_guild: fn _ -> @guild end,
        channels_for_guild: fn _ -> [] end,
        voice_states: fn _ -> [] end do
        conn =
          call_guild!(conn!(conn), :switch, %{"discord_guild_id" => @guild["id"]})

        assert redirected_to(conn) == "/billing"
        # no flash: the billing page itself communicates the paywall
        assert Phoenix.Flash.get(conn.assigns.flash, :info) == nil
        refute Tenants.get_guild(@guild["id"])
        assert get_session(conn, :billing_guild_id) == @guild["id"]
      end
    end

    test "with Stripe unconfigured, switching behaves exactly as before", %{conn: conn} do
      Application.put_env(:soundboard, Billing, [])

      with_mock Cache, [],
        get_guild: fn _ -> @guild end,
        channels_for_guild: fn _ -> [] end,
        voice_states: fn _ -> [] end do
        conn =
          call_guild!(conn!(conn), :switch, %{"discord_guild_id" => @guild["id"]})

        assert redirected_to(conn) == "/"
        assert %Tenants.Guild{} = Tenants.get_guild(@guild["id"])
      end
    end
  end

  defp webhook_header(payload, secret \\ "whsec_test") do
    ts = Integer.to_string(System.system_time(:second))
    mac = :crypto.mac(:hmac, :sha256, secret, ts <> "." <> payload) |> Base.encode16(case: :lower)
    "t=#{ts},v1=#{mac}"
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{discord_id: "discord-bill-web", username: "billweb"})
    |> Repo.insert!()
  end

  describe "GET /billing" do
    test "renders the plan cards with the current plan state", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      {:ok, guild} = Tenants.get_or_create_guild("billing-render-guild", %{name: "Render"})

      guild
      |> Tenants.Guild.changeset(%{
        max_storage_bytes: Billing.plan_cap(@stripe_env[:price_pro_monthly])
      })
      |> Repo.update!()

      conn =
        conn!(conn)
        |> assign(:current_user, nil)
        |> assign(:current_path, "/billing")
        |> assign(:presences, [])
        |> assign(:current_guild_id, guild.discord_guild_id)
        |> call!(:index)

      html = response(conn, 200)
      assert html =~ "Pick a plan"
      assert html =~ "$3.99"
      assert html =~ "$9.99"
      assert html =~ "Cancel subscription" == false
    end

    test "a guild with a remembered subscription hides the subscribe CTA and shows cancel", %{
      conn: conn
    } do
      Application.put_env(:soundboard, Billing, @stripe_env)

      {:ok, guild} = Tenants.get_or_create_guild("billing-render-sub", %{name: "Render Sub"})

      guild
      |> Tenants.Guild.changeset(%{
        max_storage_bytes: Billing.plan_cap(@stripe_env[:price_pro_monthly])
      })
      |> Repo.update!()

      Billing.remember_subscription("billing-render-sub", %{
        id: "sub_1",
        item_id: nil,
        price_id: @stripe_env[:price_pro_monthly]
      })

      html =
        conn!(conn)
        |> assign(:current_user, nil)
        |> assign(:current_path, "/billing")
        |> assign(:presences, [])
        |> assign(:current_guild_id, guild.discord_guild_id)
        |> call!(:index)
        |> response(200)

      assert html =~ "Current plan"
      assert html =~ "Cancel subscription"
      assert html =~ "Your plan"
    end
  end

  describe "checkout fallbacks" do
    test "no guild id in session or assigns redirects to /guilds with a flash", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      conn =
        conn!(conn)
        |> assign(:current_user, nil)
        |> assign(:current_guild_id, nil)
        |> call!(:checkout, %{"price_id" => "price_pro_m"})

      assert redirected_to(conn) == "/guilds"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Pick a soundboard first"
    end

    test "a checkout error redirects back to /billing with the reason", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        create_checkout_session: fn _g, _p, _o, _opts -> {:error, :stripe_down} end do
        conn =
          conn!(conn)
          |> assign(:current_user, nil)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:checkout, %{"price_id" => "price_pro_m"})

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not start checkout"
      end
    end

    test "a session without a URL redirects back to /billing", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        create_checkout_session: fn _g, _p, _o, _opts -> {:ok, %{id: "cs_1"}} end do
        conn =
          conn!(conn)
          |> assign(:current_user, nil)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:checkout, %{"price_id" => "price_pro_m"})

        assert redirected_to(conn) == "/billing"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                 "Checkout session did not return a URL"
      end
    end

    test "a checkout with no price_id redirects to /billing", %{conn: conn} do
      conn =
        conn!(conn)
        |> assign(:current_guild_id, "some-guild")
        |> call!(:checkout, %{})

      assert redirected_to(conn) == "/billing"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Pick a plan first"
    end
  end

  describe "portal" do
    test "redirects to the portal URL", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        create_portal_session: fn _g, _opts ->
          {:ok, %{url: "https://billing.stripe.com/session"}}
        end do
        conn =
          conn!(conn)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:portal)

        assert redirected_to(conn) == "https://billing.stripe.com/session"
      end
    end

    test "an error redirects back to /billing", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        create_portal_session: fn _g, _opts -> {:error, :no_customer} end do
        conn =
          conn!(conn)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:portal)

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not open billing portal"
      end
    end
  end

  describe "change" do
    test "a successful change flashes and redirects", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        change_subscription_price: fn _g, _p -> {:ok, :updated} end do
        conn =
          conn!(conn)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:change, %{"price_id" => "price_pro_y"})

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Your plan has been updated"
      end
    end

    test "no subscription redirects with an error", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        change_subscription_price: fn _g, _p -> {:error, :no_subscription} end do
        conn =
          conn!(conn)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:change, %{"price_id" => "price_pro_y"})

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No active subscription"
      end
    end

    test "an invalid price redirects with an error", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        change_subscription_price: fn _g, _p -> {:error, :invalid_price} end do
        conn =
          conn!(conn)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:change, %{"price_id" => "price_bogus"})

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Pick a plan first"
      end
    end

    test "a change with no price_id redirects to /billing", %{conn: conn} do
      conn =
        conn!(conn)
        |> assign(:current_guild_id, "some-guild")
        |> call!(:change, %{})

      assert redirected_to(conn) == "/billing"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Pick a plan first"
    end
  end

  describe "cancel" do
    test "a successful cancel flashes the period end date", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)
      period_end = DateTime.to_unix(DateTime.utc_now() |> DateTime.add(86_400))

      with_mock Billing, [:passthrough],
        cancel_subscription: fn _g -> {:ok, %{cancel_at: period_end}} end do
        conn =
          conn!(conn)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:cancel)

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "will end on"
        assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "You keep your plan until then"
      end
    end

    test "a cancel with no period end just redirects", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        cancel_subscription: fn _g -> {:ok, %{cancel_at: nil}} end do
        conn =
          conn!(conn)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:cancel)

        assert redirected_to(conn) == "/billing"
      end
    end

    test "no subscription redirects with an error", %{conn: conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      with_mock Billing, [:passthrough],
        cancel_subscription: fn _g -> {:error, :no_subscription} end do
        conn =
          conn!(conn)
          |> assign(:current_guild_id, "some-guild")
          |> call!(:cancel)

        assert redirected_to(conn) == "/billing"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No active subscription"
      end
    end
  end

  describe "webhook raw body fallback" do
    test "reads the body when no parser cached it", %{conn: _conn} do
      Application.put_env(:soundboard, Billing, @stripe_env)

      payload =
        Jason.encode!(%{
          "id" => "evt_fb",
          "type" => "customer.created",
          "data" => %{"object" => %{}}
        })

      conn =
        Plug.Test.conn(:post, "/billing/webhook", payload)
        |> init_test_session(%{})
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "missing")

      conn = Map.update!(conn, :params, &Map.put(&1, "_format", "html"))
      conn = Map.update!(conn, :params, &Map.merge(&1, %{}))
      conn = SoundboardWeb.BillingController.call(conn, :webhook)

      assert response(conn, 400)
    end
  end
end
