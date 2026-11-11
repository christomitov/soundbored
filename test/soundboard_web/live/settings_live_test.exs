defmodule SoundboardWeb.SettingsLiveTest do
  use SoundboardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Soundboard.Accounts.{ApiTokens, User}
  alias Soundboard.{Billing, Repo}
  alias Soundboard.Tenants.Guild

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

    view
    |> element("form[phx-submit=\"create_token\"]")
    |> render_submit(%{"label" => "CI Bot"})

    html = render(view)
    assert html =~ "CI Bot"

    view
    |> element("button", "Revoke")
    |> render_click()

    refute has_element?(view, "td", "CI Bot")
  end

  test "shows persisted tokens after reload", %{conn: conn, user: user} do
    {:ok, _raw, _token} = ApiTokens.generate_token(user, %{label: "Saved token"})

    {:ok, _view, html} = live(conn, "/settings")

    assert html =~ "Saved token"
    assert html =~ "Token values are shown"
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

  describe "plan card" do
    setup %{conn: conn, user: user} do
      Application.put_env(:soundboard, Billing, secret_key: "sk_test_key")
      on_exit(fn -> Application.put_env(:soundboard, Billing, []) end)

      guild =
        %Guild{}
        |> Guild.changeset(%{
          discord_guild_id: "9#{System.unique_integer([:positive])}",
          slug: "plan-#{System.unique_integer([:positive])}",
          owner_discord_id: user.discord_id,
          max_storage_bytes: 0
        })
        |> Repo.insert!()

      %{conn: init_test_session(conn, %{guild_id: guild.discord_guild_id}), guild: guild}
    end

    test "the guild's owner sees their plan and storage", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/settings")

      assert html =~ "Manage plan"
      assert html =~ "No plan"
      assert html =~ "0 B of 0 B used"
    end

    test "anyone else sees no plan card", %{conn: conn, guild: guild} do
      guild |> Ecto.Changeset.change(owner_discord_id: "someone-else") |> Repo.update!()

      {:ok, _view, html} = live(conn, "/settings")

      refute html =~ "Manage plan"
    end
  end

  test "revoking another user's token is refused", %{conn: conn} do
    {:ok, other} =
      %User{}
      |> User.changeset(%{
        username: "other_#{System.unique_integer([:positive])}",
        discord_id: "5#{System.unique_integer([:positive])}"
      })
      |> Repo.insert()

    {:ok, _raw, token} = ApiTokens.generate_token(other, %{label: "theirs"})
    {:ok, view, _html} = live(conn, "/settings")

    html = render_click(view, "revoke_token", %{"id" => to_string(token.id)})

    assert html =~ "Not allowed"
  end

  test "revoking a token that doesn't exist says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings")

    assert render_click(view, "revoke_token", %{"id" => "999999999"}) =~ "Token not found"
  end
end
