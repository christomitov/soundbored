defmodule SoundboardWeb.AccessTest do
  @moduledoc """
  The browser routes that need a signed-in user, through the router: a
  signed-out request is sent to Discord sign-in with its path kept for
  afterwards, and changes nothing.
  """

  use SoundboardWeb.ConnCase, async: false

  alias Soundboard.Tenants

  @protected [
    {:get, "/"},
    {:get, "/stats"},
    {:get, "/favorites"},
    {:get, "/settings"},
    {:get, "/guilds"},
    {:post, "/guilds/switch", %{"discord_guild_id" => "signed-out-guild"}},
    {:post, "/guilds/claim", %{"slug" => "signed-out-slug"}},
    {:get, "/onboarding"},
    {:get, "/g/some-slug"},
    {:get, "/uploads/some-file.mp3"},
    {:get, "/billing"},
    {:post, "/billing/checkout", %{"price_id" => "price_pro_m"}},
    {:post, "/billing/portal"},
    {:post, "/billing/change", %{"price_id" => "price_pro_m"}},
    {:post, "/billing/cancel"}
  ]

  test "every protected route sends a signed-out visitor to sign in" do
    enable_billing()

    for route <- @protected do
      {method, path, params} = with_params(route)
      conn = build_conn() |> init_test_session(%{}) |> dispatch(@endpoint, method, path, params)

      assert redirected_to(conn) == "/auth/discord", "#{method} #{path}"
      assert get_session(conn, :return_to) == path
    end

    refute Tenants.get_guild("signed-out-guild")
    refute Tenants.get_by_slug("signed-out-slug")
  end

  test "a session for a deleted user is cleared and sent to sign in" do
    user = user_fixture()
    Soundboard.Repo.delete!(user)

    conn = build_conn() |> sign_in(user) |> get("/")

    assert redirected_to(conn) == "/auth/discord"
    assert get_session(conn, :user_id) == nil
  end

  defp with_params({method, path}), do: {method, path, %{}}
  defp with_params(route), do: route
end
