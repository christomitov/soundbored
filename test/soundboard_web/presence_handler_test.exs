defmodule SoundboardWeb.PresenceHandlerTest do
  use ExUnit.Case, async: false

  alias SoundboardWeb.PresenceHandler

  setup do
    :persistent_term.put(:user_colors, %{})

    on_exit(fn ->
      :persistent_term.erase(:user_colors)
    end)

    :ok
  end

  test "get_user_color/1 returns stable assignments per user" do
    first = PresenceHandler.get_user_color("alice")
    second = PresenceHandler.get_user_color("alice")
    third = PresenceHandler.get_user_color("bob")

    assert first == second
    assert is_binary(third)
    refute third == ""
    refute Map.equal?(:persistent_term.get(:user_colors), %{})
  end

  test "handle_presence_diff/2 counts only presences active in the last minute" do
    now = System.system_time(:second)

    diff = %{
      joins: %{"joiner" => %{metas: [%{online_at: now - 5}]}},
      leaves: %{
        "old" => %{metas: [%{online_at: now - 300}]},
        "recent" => %{metas: [%{online_at: now - 5}]}
      }
    }

    assert PresenceHandler.handle_presence_diff(diff, 2) == 2
    assert PresenceHandler.handle_presence_diff(diff, 0) == 0
  end
end
