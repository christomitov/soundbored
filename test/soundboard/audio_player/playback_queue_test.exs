defmodule Soundboard.AudioPlayer.PlaybackQueueTest do
  use ExUnit.Case, async: false

  import Mock

  alias Soundboard.AudioPlayer.PlaybackQueue
  alias Soundboard.AudioPlayer.State

  defp base_state(overrides \\ []) do
    struct!(
      State,
      Keyword.merge(
        [
          voice_channel: {"guild-1", "channel-9"},
          current_playback: nil,
          pending_request: nil,
          interrupting: false,
          interrupt_watchdog_ref: nil,
          interrupt_watchdog_attempt: 0
        ],
        overrides
      )
    )
  end

  defp request(overrides \\ %{}) do
    Map.merge(
      %{
        guild_id: "guild-1",
        channel_id: "channel-9",
        sound_name: "intro.mp3",
        path_or_url: "/tmp/intro.mp3",
        volume: 0.8,
        actor: "System"
      },
      overrides
    )
  end

  test "build_request returns a normalized playback request" do
    with_mock Soundboard.AudioPlayer.SoundLibrary,
      get_sound_path: fn "intro.mp3" -> {:ok, {"/tmp/intro.mp3", 0.8}} end do
      assert {:ok,
              %{
                guild_id: "guild-1",
                channel_id: "channel-9",
                sound_name: "intro.mp3",
                path_or_url: "/tmp/intro.mp3",
                volume: 0.8,
                actor: "System"
              }} = PlaybackQueue.build_request({"guild-1", "channel-9"}, "intro.mp3", "System")
    end
  end

  test "build_request returns lookup errors unchanged" do
    with_mock Soundboard.AudioPlayer.SoundLibrary,
      get_sound_path: fn "missing.mp3" -> {:error, "Sound not found"} end do
      assert {:error, "Sound not found"} =
               PlaybackQueue.build_request({"guild-1", "channel-9"}, "missing.mp3", "System")
    end
  end

  test "enqueue starts playback immediately when idle" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "intro.mp3", "/tmp/intro.mp3", 0.8, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state = PlaybackQueue.enqueue(base_state(), request(), 35)

      assert %{sound_name: "intro.mp3", task_ref: ref, task_pid: pid} = state.current_playback
      assert is_reference(ref)
      assert is_pid(pid)
      assert state.pending_request == nil
      assert state.interrupting == false
      assert state.interrupt_watchdog_attempt == 0

      assert_receive :play_started

      PlaybackQueue.clear_all(state)
    end
  end

  test "enqueue interrupts current playback and schedules watchdog when audio is still playing" do
    test_pid = self()

    current = %{guild_id: "guild-1", sound_name: "old.mp3"}

    with_mocks([
      {Soundboard.Discord.Voice, [],
       [
         stop: fn "guild-1" -> send(test_pid, :stopped_voice) end,
         playing?: fn "guild-1" -> true end
       ]}
    ]) do
      state = PlaybackQueue.enqueue(base_state(current_playback: current), request(), 35)

      assert_receive :stopped_voice
      assert state.pending_request.sound_name == "intro.mp3"
      assert state.interrupting == true
      assert state.interrupt_watchdog_attempt == 1
      assert is_reference(state.interrupt_watchdog_ref)
    end
  end

  test "enqueue fast-path starts pending playback when stop finishes immediately" do
    test_pid = self()

    current = %{guild_id: "guild-1", sound_name: "old.mp3"}

    with_mocks([
      {Soundboard.Discord.Voice, [],
       [
         stop: fn "guild-1" -> send(test_pid, :stopped_voice) end,
         playing?: fn "guild-1" -> false end
       ]},
      {Soundboard.AudioPlayer.PlaybackEngine, [],
       [
         play: fn "guild-1", "channel-9", "intro.mp3", "/tmp/intro.mp3", 0.8, "System" ->
           send(test_pid, :play_started)
           :ok
         end
       ]}
    ]) do
      state = PlaybackQueue.enqueue(base_state(current_playback: current), request(), 35)

      assert_receive :stopped_voice
      assert_receive :play_started
      assert %{sound_name: "intro.mp3"} = state.current_playback
      assert state.pending_request == nil
      assert state.interrupting == false

      PlaybackQueue.clear_all(state)
    end
  end

  test "clear_all resets playback, pending, and interrupt state" do
    timer_ref = Process.send_after(self(), :unused_watchdog, 5_000)

    state =
      base_state(
        current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
        pending_request: request(%{sound_name: "next.mp3"}),
        interrupting: true,
        interrupt_watchdog_ref: timer_ref,
        interrupt_watchdog_attempt: 4
      )
      |> PlaybackQueue.clear_all()

    assert state.current_playback == nil
    assert state.pending_request == nil
    assert state.interrupting == false
    assert state.interrupt_watchdog_ref == nil
    assert state.interrupt_watchdog_attempt == 0
  end

  test "handle_task_result marks successful playback task as completed" do
    current = %{
      guild_id: "guild-1",
      sound_name: "intro.mp3",
      task_pid: self(),
      task_ref: make_ref()
    }

    state =
      base_state(current_playback: current)
      |> PlaybackQueue.handle_task_result(:ok)

    assert %{sound_name: "intro.mp3", task_pid: nil, task_ref: nil} = state.current_playback
  end

  test "handle_task_result clears failed playback and starts pending request" do
    test_pid = self()

    current = %{guild_id: "guild-1", sound_name: "old.mp3"}

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          current_playback: current,
          pending_request:
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
        )
        |> PlaybackQueue.handle_task_result(:error)

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.pending_request == nil

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_task_result drops pending playback when the voice channel no longer matches" do
    state =
      base_state(
        voice_channel: {"guild-1", "other-channel"},
        current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
        pending_request: request(%{sound_name: "next.mp3"})
      )
      |> PlaybackQueue.handle_task_result(:error)

    assert state.current_playback == nil
    assert state.pending_request == nil
  end

  test "handle_task_down clears crashed playback and starts pending request" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
          pending_request:
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
        )
        |> PlaybackQueue.handle_task_down(:boom)

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_interrupt_watchdog starts pending playback once current playback is already gone" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          interrupting: true,
          interrupt_watchdog_attempt: 1,
          current_playback: nil,
          pending_request:
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
        )
        |> PlaybackQueue.handle_interrupt_watchdog("guild-1", 1, 3, 35)

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.interrupting == false
      assert state.interrupt_watchdog_attempt == 0

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_interrupt_watchdog retries stop and reschedules when audio is still playing" do
    test_pid = self()

    with_mock Soundboard.Discord.Voice,
      stop: fn "guild-1" -> send(test_pid, :stopped_voice) end,
      playing?: fn "guild-1" -> true end do
      state =
        base_state(
          interrupting: true,
          interrupt_watchdog_attempt: 1,
          current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
          pending_request: request()
        )
        |> PlaybackQueue.handle_interrupt_watchdog("guild-1", 1, 3, 35)

      assert_receive :stopped_voice
      assert state.current_playback.sound_name == "old.mp3"
      assert state.pending_request.sound_name == "intro.mp3"
      assert state.interrupting == true
      assert state.interrupt_watchdog_attempt == 2
      assert is_reference(state.interrupt_watchdog_ref)
    end
  end

  test "handle_interrupt_watchdog clears current playback when audio is already stopped" do
    test_pid = self()

    with_mocks([
      {Soundboard.Discord.Voice, [], [playing?: fn "guild-1" -> false end]},
      {Soundboard.AudioPlayer.PlaybackEngine, [],
       [
         play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
           send(test_pid, :play_started)
           :ok
         end
       ]}
    ]) do
      state =
        base_state(
          interrupting: true,
          interrupt_watchdog_attempt: 1,
          current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
          pending_request:
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
        )
        |> PlaybackQueue.handle_interrupt_watchdog("guild-1", 1, 3, 35)

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.interrupting == false
      assert state.interrupt_watchdog_attempt == 0

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_interrupt_watchdog forces the latest request after max attempts" do
    test_pid = self()

    with_mocks([
      {Soundboard.Discord.Voice, [], [stop: fn "guild-1" -> send(test_pid, :stopped_voice) end]},
      {Soundboard.AudioPlayer.PlaybackEngine, [],
       [
         play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
           send(test_pid, :play_started)
           :ok
         end
       ]}
    ]) do
      state =
        base_state(
          interrupting: true,
          interrupt_watchdog_attempt: 3,
          current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
          pending_request:
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
        )
        |> PlaybackQueue.handle_interrupt_watchdog("guild-1", 3, 3, 35)

      assert_receive :stopped_voice
      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.interrupting == false
      assert state.interrupt_watchdog_attempt == 0

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_interrupt_watchdog is a no-op when not interrupting" do
    state = base_state() |> PlaybackQueue.handle_interrupt_watchdog("guild-1", 1, 3, 35)

    assert state == base_state()
  end

  test "handle_playback_finished clears matching playback and starts the pending request" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          current_playback: %{guild_id: "guild-1", sound_name: "old.mp3"},
          pending_request:
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
        )
        |> PlaybackQueue.handle_playback_finished("guild-1")

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.pending_request == nil

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_playback_finished resumes pending playback after interrupt flow finishes" do
    test_pid = self()

    with_mock Soundboard.AudioPlayer.PlaybackEngine,
      play: fn "guild-1", "channel-9", "next.mp3", "/tmp/next.mp3", 0.6, "System" ->
        send(test_pid, :play_started)
        :ok
      end do
      state =
        base_state(
          voice_channel: {"guild-1", "channel-9"},
          current_playback: %{guild_id: "other-guild", sound_name: "other.mp3"},
          interrupting: true,
          pending_request:
            request(%{sound_name: "next.mp3", path_or_url: "/tmp/next.mp3", volume: 0.6})
        )
        |> PlaybackQueue.handle_playback_finished("guild-1")

      assert_receive :play_started
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.interrupting == false

      PlaybackQueue.clear_all(state)
    end
  end

  test "handle_playback_finished ignores unrelated guilds" do
    state =
      base_state(current_playback: %{guild_id: "guild-1", sound_name: "intro.mp3"})
      |> PlaybackQueue.handle_playback_finished("other-guild")

    assert state.current_playback.sound_name == "intro.mp3"
  end
end
