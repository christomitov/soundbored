defmodule SoundboardWeb.LiveAccessTest do
  use SoundboardWeb.ConnCase, async: false

  @pages ["/", "/stats", "/favorites", "/settings"]

  test "signed-out visitors are sent to Discord sign-in from every page" do
    for path <- @pages do
      assert redirected_to(get(build_conn(), path)) == "/auth/discord", path
    end
  end

  test "a session whose user no longer exists is signed out" do
    for path <- @pages do
      conn = build_conn() |> init_test_session(%{user_id: -1}) |> get(path)

      assert redirected_to(conn) == "/auth/discord", path
      refute get_session(conn, :user_id)
    end
  end
end
