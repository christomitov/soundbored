defmodule SoundboardWeb.Plugs.AppGateTest do
  @moduledoc """
  Web tests for the app gate: unlocked when billing is dormant, and on hosted
  unlocked only for a signed-in user whose session guild has an active
  subscription. Gated requests are redirected to /billing (guild picked, no
  subscription) or /guilds (no guild picked) and the navbar assign is always set.
  """

  use SoundboardWeb.ConnCase, async: false

  alias Soundboard.Billing
  alias Soundboard.Repo
  alias Soundboard.Tenants
  alias SoundboardWeb.Plugs.AppGate

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

  defp run(conn, mode \\ :gate) do
    conn
    |> init_test_session(%{})
    |> fetch_flash()
    |> AppGate.call(mode)
  end

  test "assign_only sets the navbar flag without redirecting", %{conn: conn} do
    conn = run(conn, :assign_only)
    assert conn.assigns.app_unlocked == true
    refute conn.halted
  end

  test "billing dormant means everything is unlocked", %{conn: conn} do
    Application.put_env(:soundboard, Billing, [])

    conn = run(init_test_session(conn, %{guild_id: "whatever"}))

    assert conn.assigns.app_unlocked == true
    refute conn.halted
  end

  test "hosted with no picked guild redirects to /guilds", %{conn: conn} do
    Application.put_env(:soundboard, Billing, @stripe_env)

    conn = run(conn)

    assert redirected_to(conn) == "/guilds"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Pick a soundboard to continue"
    assert conn.halted
    assert conn.assigns.app_unlocked == false
  end

  test "hosted with a guild but no subscription redirects to /billing", %{conn: conn} do
    Application.put_env(:soundboard, Billing, @stripe_env)

    conn = run(init_test_session(conn, %{guild_id: "no-sub-guild"}))

    assert redirected_to(conn) == "/billing"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "That soundboard needs an active subscription"

    assert conn.halted
  end

  test "hosted with an active subscription passes", %{conn: conn} do
    Application.put_env(:soundboard, Billing, @stripe_env)

    {:ok, guild} = Tenants.get_or_create_guild("appgate-guild", %{name: "Gate"})

    guild
    |> Tenants.Guild.changeset(%{
      max_storage_bytes: Billing.plan_cap(@stripe_env[:price_pro_monthly])
    })
    |> Repo.update!()

    conn = run(init_test_session(conn, %{guild_id: guild.discord_guild_id}))

    assert conn.assigns.app_unlocked == true
    refute conn.halted
  end
end
