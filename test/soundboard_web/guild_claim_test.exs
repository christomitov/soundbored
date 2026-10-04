defmodule SoundboardWeb.GuildClaimTest do
  @moduledoc """
  Unit tests for SB-2 slug claim: `POST /guilds/claim` (claim a subdomain for
  the session's current guild) and `GET /g/:slug` (resolve a tenant by slug
  and scope the app to it).
  """

  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.Repo
  alias Soundboard.Tenants

  describe "POST /guilds/claim" do
    test "claiming an available slug updates the guild and flashes the URL", %{conn: conn} do
      {:ok, _} = Tenants.get_or_create_guild("claim-success")

      conn =
        call!(
          conn!(conn) |> assign(:current_guild_id, "claim-success"),
          :claim,
          %{"slug" => "My-Server"}
        )

      assert redirected_to(conn) == "/guilds"
      assert Tenants.get_by_slug("my-server").discord_guild_id == "claim-success"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "https://app.soundbored.app/g/my-server"
    end

    test "a duplicate slug is rejected without mutating anything", %{conn: conn} do
      {:ok, _} = Tenants.claim_slug("owner-a", "taken-slug")

      conn =
        call!(
          conn!(conn) |> assign(:current_guild_id, "owner-b"),
          :claim,
          %{"slug" => "taken-slug"}
        )

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not available"
      assert Tenants.get_by_slug("taken-slug").discord_guild_id == "owner-a"
      refute Tenants.get_guild("owner-b")
    end

    test "a reserved slug is rejected without mutating anything", %{conn: conn} do
      conn =
        call!(
          conn!(conn) |> assign(:current_guild_id, "owner-c"),
          :claim,
          %{"slug" => "admin"}
        )

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not available"
      refute Tenants.get_by_slug("admin")
      refute Tenants.get_guild("owner-c")
    end

    test "an unauthenticated POST redirects to auth and mutates nothing", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_csrf_token()
        |> post("/guilds/claim", %{"slug" => "sneaky-slug", "_csrf_token" => csrf_token()})

      assert redirected_to(conn) == "/auth/discord"
      refute Tenants.get_by_slug("sneaky-slug")
    end
  end

  describe "GET /g/:slug" do
    test "resolves the tenant, sets the session guild, and scopes the app", %{conn: conn} do
      {:ok, _} = Tenants.claim_slug("g-resolved", "resolve-me")
      user = insert_user!()

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id})
        |> get("/g/resolve-me")

      assert redirected_to(conn) == "/"
      assert get_session(conn, :guild_id) == "g-resolved"

      # A follow-up request is scoped to the resolved tenant by the plug.
      with_mock(EDA.Cache, [],
        guilds: fn -> [%{"id" => "g-resolved", "name" => "Resolved"}] end,
        channels_for_guild: fn _ -> [] end,
        voice_states: fn _ -> [] end
      ) do
        scoped =
          conn
          |> recycle()
          |> get("/guilds")

        assert scoped.assigns.current_guild_id == "g-resolved"
      end
    end

    test "an unknown slug 404s without creating a tenant row", %{conn: conn} do
      user = insert_user!()

      conn =
        conn
        |> init_test_session(%{"user_id" => user.id})
        |> get("/g/unknown")

      assert response(conn, 404)
      refute Tenants.get_by_slug("unknown")
    end

    test "a signed-out visit stashes :pending_slug across the auth redirect", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get("/g/wanted-slug")

      assert redirected_to(conn) == "/auth/discord"
      assert get_session(conn, :pending_slug) == "wanted-slug"
    end

    test "the OAuth callback lands on /g/:pending_slug and clears it", %{conn: conn} do
      auth_data = %{uid: "999888", info: %{nickname: "SlugUser", image: nil}}

      conn =
        conn
        |> init_test_session(%{"pending_slug" => "wanted-slug"})
        |> assign(:ueberauth_auth, auth_data)
        |> get("/auth/discord/callback")

      assert redirected_to(conn) == "/g/wanted-slug"
      assert get_session(conn, :user_id)
      assert get_session(conn, :pending_slug) == nil
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp conn!(conn),
    do:
      conn
      |> init_test_session(%{})
      |> fetch_query_params()
      |> fetch_flash()
      |> Map.update!(:params, &Map.put(&1, "_format", "html"))

  defp call!(conn, action, params) do
    conn = Map.update!(conn, :params, &Map.merge(&1, params))
    SoundboardWeb.GuildController.call(conn, action)
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{
      discord_id: "u#{System.unique_integer([:positive])}",
      username: "slug-tester",
      avatar: nil
    })
    |> Repo.insert!()
  end

  # Session-bound CSRF state for router-level POSTs: Plug.CSRFProtection keeps
  # its unmasked token in the process dictionary; the masked variant is what a
  # form would carry as the `_csrf_token` param. Same process, so this works
  # under Phoenix.ConnTest dispatch.
  defp put_csrf_token(conn) do
    Plug.CSRFProtection.get_csrf_token()
    put_session(conn, "_csrf_token", Process.get(:plug_unmasked_csrf_token))
  end

  defp csrf_token, do: Plug.CSRFProtection.get_csrf_token()
end
