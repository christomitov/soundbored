defmodule SoundboardWeb.Components.Layouts.NavbarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SoundboardWeb.Components.Layouts.Navbar

  test "renders public navigation links" do
    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/",
        current_user: nil,
        presences: %{}
      )

    assert html =~ "SoundBored"
    assert html =~ "Sounds"
    assert html =~ "Favorites"
    assert html =~ "Stats"
    refute html =~ "Settings"
  end

  test "renders settings link and deduplicated presences for authenticated users" do
    html =
      render_component(Navbar,
        id: "navbar",
        current_path: "/settings",
        current_user: %{id: 1, username: "owner"},
        presences: %{
          "1" => %{metas: [%{user: %{username: "alice", avatar: "alice.png"}}]},
          "2" => %{metas: [%{user: %{username: "alice", avatar: "alice.png"}}]},
          "3" => %{metas: [%{user: %{username: "bob", avatar: "bob.png"}}]}
        }
      )

    assert html =~ "Settings"
    assert html =~ "user-alice"
    assert html =~ "user-bob"

    # Duplicated presence entries for the same user should only render once per menu section.
    assert length(Regex.scan(~r/user-alice/, html)) == 2
  end

  test "toggle-mobile-menu flips show_mobile_menu assign" do
    {:ok, socket} = Navbar.mount(%Phoenix.LiveView.Socket{})

    {:noreply, socket} = Navbar.handle_event("toggle-mobile-menu", %{}, socket)
    assert socket.assigns.show_mobile_menu

    {:noreply, socket} = Navbar.handle_event("toggle-mobile-menu", %{}, socket)
    refute socket.assigns.show_mobile_menu
  end
end
