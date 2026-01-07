defmodule SoundboardWeb.SettingsLiveTest do
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Soundboard.Accounts.{Tenant, Tenants, User}
  alias Soundboard.{Repo, Sound}

  setup %{conn: conn} do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "apitok_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    authed_conn =
      conn
      |> Map.replace!(:secret_key_base, SoundboardWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_id: user.id})

    %{conn: authed_conn, user: user, tenant: tenant}
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

  test "renders plan information when running in pro edition", %{
    conn: conn,
    tenant: tenant,
    user: user
  } do
    original = Application.get_env(:soundboard, :edition, :community)
    Application.put_env(:soundboard, :edition, :pro)

    on_exit(fn ->
      Application.put_env(:soundboard, :edition, original)
    end)

    {:ok, updated_tenant} =
      tenant
      |> Tenant.changeset(%{plan: :pro, max_sounds: 2})
      |> Repo.update()

    {:ok, _sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "pro-test.mp3",
        user_id: user.id,
        tenant_id: updated_tenant.id
      })
      |> Repo.insert()

    {:ok, _view, html} = live(conn, "/settings")
    assert html =~ "Plan &amp; Billing"
    assert html =~ "Pro"
    assert html =~ ~r/(2 used|1 \/ 2 used)/
  end
end
