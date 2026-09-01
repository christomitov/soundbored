defmodule SoundboardWeb.Components.Layouts.NavbarTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SoundboardWeb.Components.Layouts.Navbar

  test "renders public navigation links" do
    html =
      render_component(&Navbar.navbar/1,
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
      render_component(&Navbar.navbar/1,
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
    assert Enum.count(Regex.scan(~r/user-alice/, html)) == 2
  end
end
