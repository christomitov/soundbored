defmodule SoundboardWeb.GuildControllerTest do
  @moduledoc """
  Picking a soundboard, through the router: the guild list, switching
  (provisioning the tenant, or the paywall on hosted), claiming a subdomain
  slug, and opening a soundboard by `/g/:slug`. Only the Discord cache is
  mocked.
  """

  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias EDA.Cache
  alias Soundboard.Tenants

  @bot_guild %{"id" => "guild-switch", "name" => "Switch Guild"}

  setup_with_mocks([
    {Cache, [:passthrough],
     guilds: fn -> [@bot_guild] end,
     get_guild: fn
       "guild-switch" -> @bot_guild
       "guild-closed" -> %{"id" => "guild-closed", "name" => "Closed"}
       _ -> nil
     end,
     channels_for_guild: fn _ -> [] end,
     voice_states: fn _ -> [] end,
     fetch_member: fn
       "guild-closed", _ -> {:error, :not_found}
       _, _ -> {:ok, %{}}
     end}
  ]) do
    :ok
  end

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: sign_in(conn, user), user: user}
  end

  describe "GET /guilds" do
    test "lists the bot's guilds", %{conn: conn} do
      assert conn |> get("/guilds") |> html_response(200) =~ "Switch Guild"
    end
  end

  describe "POST /guilds/switch" do
    test "provisions the tenant with the switcher as owner", %{conn: conn, user: user} do
      conn = post(conn, "/guilds/switch", %{"discord_guild_id" => "guild-switch"})

      assert redirected_to(conn) == "/"
      assert get_session(conn, :guild_id) == "guild-switch"
      assert Tenants.get_guild("guild-switch").owner_discord_id == user.discord_id
    end

    test "refuses a guild the bot is not in", %{conn: conn} do
      conn = post(conn, "/guilds/switch", %{"discord_guild_id" => "guild-nope"})

      assert redirected_to(conn) == "/guilds"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Bot is not a member of that guild"
      refute Tenants.get_guild("guild-nope")
    end

    test "on hosted, an unpaid guild goes to checkout without a tenant row", %{conn: conn} do
      enable_billing()

      conn = post(conn, "/guilds/switch", %{"discord_guild_id" => "guild-switch"})

      assert redirected_to(conn) == "/billing"
      assert get_session(conn, :billing_guild_id) == "guild-switch"
      refute Tenants.get_guild("guild-switch")
    end
  end

  describe "POST /guilds/claim" do
    setup %{conn: conn, user: user} do
      {:ok, _} = Tenants.get_or_create_guild("guild-claim", %{owner_discord_id: user.discord_id})
      %{conn: init_test_session(conn, %{guild_id: "guild-claim"})}
    end

    test "claims a free slug for the owner's guild", %{conn: conn} do
      conn = post(conn, "/guilds/claim", %{"slug" => "My-Server"})

      assert redirected_to(conn) == "/guilds"
      assert Tenants.get_by_slug("my-server").discord_guild_id == "guild-claim"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "https://dashboard.soundbored.app/g/my-server"
    end

    test "refuses taken and reserved slugs without changing anything", %{conn: conn} do
      {:ok, _} = Tenants.claim_slug("other-guild", "taken-slug")

      for slug <- ["taken-slug", "admin"] do
        conn = post(conn, "/guilds/claim", %{"slug" => slug})

        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "That subdomain is not available"
      end

      assert Tenants.get_by_slug("taken-slug").discord_guild_id == "other-guild"
      refute Tenants.get_by_slug("admin")
      assert Tenants.get_guild("guild-claim").slug == "guild-guild-claim"
    end
  end

  describe "GET /g/:slug" do
    test "opens that soundboard for the rest of the session", %{conn: conn} do
      {:ok, _} = Tenants.claim_slug("g-resolved", "resolve-me")

      conn = get(conn, "/g/resolve-me")

      assert redirected_to(conn) == "/"
      assert get_session(conn, :guild_id) == "g-resolved"

      assert conn
             |> recycle()
             |> get("/guilds")
             |> Map.get(:assigns)
             |> Map.get(:current_guild_id) == "g-resolved"
    end

    test "is a 404 for an unknown slug, creating nothing", %{conn: conn} do
      assert conn |> get("/g/unknown") |> response(404)
      refute Tenants.get_by_slug("unknown")
    end

    test "a signed-out visit keeps the slug for after sign-in" do
      conn = build_conn() |> init_test_session(%{}) |> get("/g/wanted-slug")

      assert redirected_to(conn) == "/auth/discord"
      assert get_session(conn, :pending_slug) == "wanted-slug"
    end
  end

  describe "a guild the user is not a member of" do
    setup do
      {:ok, _} = Tenants.claim_slug("guild-closed", "closed")
      :ok
    end

    test "cannot be switched to", %{conn: conn} do
      conn = post(conn, "/guilds/switch", %{"discord_guild_id" => "guild-closed"})

      assert redirected_to(conn) == "/guilds"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You are not a member of that Discord server"

      assert get_session(conn, :guild_id) == Tenants.default_guild_id()
      refute Tenants.get_guild("guild-closed").owner_discord_id
    end

    test "cannot be opened by slug", %{conn: conn} do
      conn = get(conn, "/g/closed")

      assert redirected_to(conn) == "/guilds"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You are not a member of that Discord server"

      assert get_session(conn, :guild_id) == Tenants.default_guild_id()
    end
  end

  test "a member who is not the owner cannot claim the guild's slug", %{conn: conn} do
    {:ok, _} =
      Tenants.get_or_create_guild("guild-owned", %{
        slug: "owned",
        owner_discord_id: "someone-else"
      })

    conn =
      conn
      |> init_test_session(%{guild_id: "guild-owned"})
      |> post("/guilds/claim", %{"slug" => "hijacked"})

    assert Tenants.get_guild("guild-owned").slug == "owned"
    assert redirected_to(conn) == "/guilds"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Only the soundboard's owner can claim its subdomain"
  end
end
