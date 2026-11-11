defmodule SoundboardWeb.Plugs.AppGateTest do
  @moduledoc """
  The hosted paywall, through the router: app pages need a picked soundboard
  with an active subscription, while the setup pages that unlock it stay open.
  """

  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.{Billing, Repo, Tenants}

  setup %{conn: conn} do
    enable_billing()
    user = user_fixture()

    {:ok, guild} =
      Tenants.get_or_create_guild("gate-unpaid", %{owner_discord_id: user.discord_id})

    %{conn: conn, user: user, guild: guild}
  end

  test "app pages send a picked but unpaid soundboard to /billing", %{conn: conn, user: user} do
    for path <- ["/", "/stats", "/favorites", "/settings"] do
      conn = conn |> sign_in(user, %{guild_id: "gate-unpaid"}) |> get(path)

      assert redirected_to(conn) == "/billing", path

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "That soundboard needs an active subscription"
    end
  end

  test "app pages send a user with no soundboard picked to /guilds", %{conn: conn, user: user} do
    conn = conn |> sign_in(user) |> get("/")

    assert redirected_to(conn) == "/guilds"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Pick a soundboard to continue"
  end

  test "the setup pages stay open while the app is locked", %{conn: conn, user: user} do
    with_mock Stripe.Subscription, list: fn _params, _opts -> {:ok, %Stripe.List{data: []}} end do
      for path <- ["/guilds", "/onboarding", "/billing"] do
        conn = conn |> sign_in(user, %{guild_id: "gate-unpaid"}) |> get(path)

        assert html_response(conn, 200), path
        assert conn.assigns.app_unlocked == false
      end
    end
  end

  test "a paid soundboard opens the app", %{conn: conn, user: user, guild: guild} do
    guild
    |> Tenants.Guild.changeset(%{max_storage_bytes: Billing.plan_cap("price_pro_m")})
    |> Repo.update!()

    assert conn |> sign_in(user, %{guild_id: "gate-unpaid"}) |> get("/") |> html_response(200)
  end
end
