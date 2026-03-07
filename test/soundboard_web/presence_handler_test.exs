defmodule SoundboardWeb.PresenceHandlerTest do
  use ExUnit.Case, async: false

  import Mock

  alias SoundboardWeb.PresenceHandler

  setup do
    :persistent_term.put(:user_colors, %{})

    on_exit(fn ->
      :persistent_term.erase(:user_colors)
    end)

    :ok
  end

  test "start_link/1 returns the named server" do
    pid =
      case PresenceHandler.start_link([]) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    assert Process.alive?(pid)
  end

  test "init/1 resets the color cache" do
    :persistent_term.put(:user_colors, %{"stale" => "color"})

    assert {:ok, %{}} = PresenceHandler.init(:ok)
    assert :persistent_term.get(:user_colors) == %{}
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

  test "track_presence/2 tracks connected users and anonymous visitors" do
    test_pid = self()

    with_mock SoundboardWeb.Presence,
      track: fn pid, topic, socket_id, payload ->
        send(test_pid, {:tracked, pid, topic, socket_id, payload})
        :ok
      end,
      list: fn _topic -> %{} end do
      socket = %Phoenix.LiveView.Socket{id: "abcdef123", transport_pid: self()}
      user = %{username: "alice", avatar: "avatar.png"}

      assert :ok = PresenceHandler.track_presence(socket, user)

      assert_receive {:tracked, _pid, "soundboard:presence", "abcdef123",
                      %{user: %{username: "alice", avatar: "avatar.png", color: color}}}

      assert is_binary(color)

      anonymous_socket = %Phoenix.LiveView.Socket{id: "anon999", transport_pid: self()}

      assert :ok = PresenceHandler.track_presence(anonymous_socket, nil)

      assert_receive {:tracked, _pid, "soundboard:presence", "anon999",
                      %{user: %{username: "Anonymous anon99", avatar: nil}}}
    end
  end

  test "track_presence/2 is a no-op for disconnected sockets" do
    with_mock SoundboardWeb.Presence, track: fn _, _, _, _ -> flunk("should not track") end do
      socket = %Phoenix.LiveView.Socket{id: "offline", transport_pid: nil}
      assert PresenceHandler.track_presence(socket, nil) == nil
    end
  end

  test "get_presence_count/0 and handle_presence_diff/2 count only active presences" do
    now = System.system_time(:second)

    presences = %{
      "fresh" => %{metas: [%{online_at: now - 10}]},
      "stale" => %{metas: [%{online_at: now - 120}]},
      "empty" => %{metas: []}
    }

    with_mock SoundboardWeb.Presence, list: fn _topic -> presences end do
      assert PresenceHandler.get_presence_count() == 1
    end

    diff = %{
      joins: %{
        "joiner" => %{metas: [%{online_at: now - 5}]}
      },
      leaves: %{
        "old" => %{metas: [%{online_at: now - 300}]},
        "recent" => %{metas: [%{online_at: now - 5}]}
      }
    }

    assert PresenceHandler.handle_presence_diff(diff, 2) == 2
    assert PresenceHandler.handle_presence_diff(diff, 0) == 0
  end
end
