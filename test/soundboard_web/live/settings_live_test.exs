defmodule SoundboardWeb.SettingsLiveTest do
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Soundboard.Accounts.{ApiTokens, User}
  alias Soundboard.Repo

  setup %{conn: conn} do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "apitok_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg"
      })
      |> Repo.insert()

    authed_conn =
      conn
      |> Map.replace!(:secret_key_base, SoundboardWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_id: user.id})

    %{conn: authed_conn, user: user}
  end

  test "can create and revoke tokens via live view", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    # Create token
    view
    |> element("form[phx-submit=\"create_token\"]")
    |> render_submit(%{"label" => "CI Bot"})

    # Ensure it appears in the table
    html = render(view)
    assert html =~ "CI Bot"

    # Revoke the first token button
    view
    |> element("button", "Revoke")
    |> render_click()

    # Should disappear from the table
    refute has_element?(view, "td", "CI Bot")
  end

  test "shows persisted tokens after reload", %{conn: conn, user: user} do
    {:ok, raw, _token} = ApiTokens.generate_token(user, %{label: "Saved token"})

    {:ok, _view, html} = live(conn, "/settings")

    assert html =~ "Saved token"
    assert html =~ raw
  end

  test "shows upload API documentation", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings")

    assert html =~ "POST /api/sounds"
    assert html =~ "Upload local file (multipart/form-data)"
    assert html =~ "Upload from URL (JSON)"
    assert html =~ "tags[]"
    assert html =~ "is_join_sound"
    assert html =~ "is_leave_sound"
  end
end
