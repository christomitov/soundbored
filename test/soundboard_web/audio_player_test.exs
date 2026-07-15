defmodule Soundboard.AudioPlayerTest do
  use ExUnit.Case, async: false

  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.AudioPlayer
  alias Soundboard.AudioPlayer.{State, VoiceSession}
  alias Soundboard.Discord.Handler.{AutoJoinPolicy, VoicePresence}
  alias Soundboard.Discord.Voice

  setup do
    original_state = :sys.get_state(AudioPlayer)

    on_exit(fn ->
      :sys.replace_state(AudioPlayer, fn _ -> original_state end)
    end)

    :ok
  end

  test "forces leave and rejoin when EDA loses its channel after a gateway disconnect" do
    test_pid = self()

    state = %State{
      voice_channel: {"guild-1", "channel-1"},
      current_playback: nil,
      pending_request: nil,
      interrupting: false,
      interrupt_watchdog_ref: nil,
      interrupt_watchdog_attempt: 0
    }

    with_mock Voice,
      channel_id: fn "guild-1" -> nil end,
      ready?: fn "guild-1" -> false end,
      playing?: fn "guild-1" -> false end,
      leave_channel: fn "guild-1" -> send(test_pid, :left_channel) end,
      join_channel: fn "guild-1", "channel-1" -> send(test_pid, :joined_channel) end do
      assert VoiceSession.maintain_connection(state) == state
      assert_received :left_channel
      assert_received :joined_channel
    end
  end

  test "continues voice maintenance when playback status is unavailable" do
    test_pid = self()

    :sys.replace_state(AudioPlayer, fn _ ->
      %State{
        voice_channel: {"guild-1", "channel-1"},
        current_playback: nil,
        pending_request: nil,
        interrupting: false,
        interrupt_watchdog_ref: nil,
        interrupt_watchdog_attempt: 0
      }
    end)

    with_mock Voice,
      channel_id: fn "guild-1" -> "channel-1" end,
      ready?: fn "guild-1" -> false end,
      playing?: fn "guild-1" -> raise "playback status unavailable" end,
      leave_channel: fn "guild-1" -> :ok end,
      join_channel: fn "guild-1", "channel-1" ->
        send(test_pid, :join_attempted)
        :ok
      end do
      send(AudioPlayer, :check_voice_connection)

      # leave→rejoin includes a 1s sleep between leave and join
      assert_receive :join_attempted, 2_000
    end
  end

  describe "idle timeout" do
    test "schedules idle timeout when voice channel is set (play mode)" do
      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: nil, idle_timeout_ref: nil}
      end)

      AudioPlayer.set_voice_channel("guild-1", "ch-1")
      # Sync: the call queues after the cast, ensuring the cast is processed first
      AudioPlayer.current_voice_channel()

      state = :sys.get_state(AudioPlayer)
      assert state.voice_channel == {"guild-1", "ch-1"}
      assert state.idle_timeout_ref != nil
    end

    test "does not schedule idle timeout in presence mode" do
      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: nil, idle_timeout_ref: nil}
      end)

      with_mock AutoJoinPolicy, mode: fn -> :presence end do
        AudioPlayer.set_voice_channel("guild-1", "ch-1")
        AudioPlayer.current_voice_channel()

        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == {"guild-1", "ch-1"}
        assert state.idle_timeout_ref == nil
      end
    end

    test "does not schedule idle timeout in false mode on join" do
      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: nil, idle_timeout_ref: nil}
      end)

      with_mock AutoJoinPolicy, mode: fn -> false end do
        AudioPlayer.set_voice_channel("guild-1", "ch-1")
        AudioPlayer.current_voice_channel()

        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == {"guild-1", "ch-1"}
        assert state.idle_timeout_ref == nil
      end
    end

    test "cancels idle timeout when voice channel is cleared" do
      :sys.replace_state(AudioPlayer, fn state ->
        %{
          state
          | voice_channel: {"guild-1", "ch-1"},
            idle_timeout_ref: {make_ref(), make_ref()}
        }
      end)

      AudioPlayer.set_voice_channel(nil, nil)
      AudioPlayer.current_voice_channel()

      state = :sys.get_state(AudioPlayer)
      assert state.voice_channel == nil
      assert state.idle_timeout_ref == nil
    end

    test "resets idle timeout when a sound is played (play mode)" do
      token = make_ref()

      :sys.replace_state(AudioPlayer, fn state ->
        %{
          state
          | voice_channel: {"guild-1", "ch-1"},
            idle_timeout_ref: {make_ref(), token},
            current_playback: nil,
            pending_request: nil,
            interrupting: false,
            interrupt_watchdog_attempt: 0
        }
      end)

      with_mocks([
        {Soundboard.AudioPlayer.SoundLibrary, [],
         [get_sound_path: fn "test.mp3" -> {:ok, {"/path/test.mp3", 1.0}} end]},
        {Soundboard.AudioPlayer.PlaybackEngine, [], [play: fn _, _, _, _, _, _ -> :ok end]}
      ]) do
        AudioPlayer.play_sound("test.mp3", "actor")
        AudioPlayer.current_voice_channel()

        state = :sys.get_state(AudioPlayer)
        # A new token means the timer was reset
        {_ref, new_token} = state.idle_timeout_ref
        assert new_token != token
      end
    end

    test "does not reset idle timeout when a sound is played in presence mode" do
      token = make_ref()

      :sys.replace_state(AudioPlayer, fn state ->
        %{
          state
          | voice_channel: {"guild-1", "ch-1"},
            idle_timeout_ref: {make_ref(), token},
            current_playback: nil,
            pending_request: nil,
            interrupting: false,
            interrupt_watchdog_attempt: 0
        }
      end)

      with_mocks([
        {AutoJoinPolicy, [], [mode: fn -> :presence end]},
        {Soundboard.AudioPlayer.SoundLibrary, [],
         [get_sound_path: fn "test.mp3" -> {:ok, {"/path/test.mp3", 1.0}} end]},
        {Soundboard.AudioPlayer.PlaybackEngine, [], [play: fn _, _, _, _, _, _ -> :ok end]}
      ]) do
        AudioPlayer.play_sound("test.mp3", "actor")
        AudioPlayer.current_voice_channel()

        state = :sys.get_state(AudioPlayer)
        {_ref, unchanged_token} = state.idle_timeout_ref
        assert unchanged_token == token
      end
    end

    test "idle timeout fires and leaves the voice channel" do
      test_pid = self()
      token = make_ref()

      :sys.replace_state(AudioPlayer, fn state ->
        %{
          state
          | voice_channel: {"guild-1", "ch-1"},
            idle_timeout_ref: {make_ref(), token},
            current_playback: nil
        }
      end)

      with_mock Voice,
        leave_channel: fn "guild-1" ->
          send(test_pid, :leave_called)
          :ok
        end do
        send(AudioPlayer, {:idle_timeout, token})
        assert_receive :leave_called, 1_000

        AudioPlayer.current_voice_channel()
        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == nil
        assert state.idle_timeout_ref == nil
      end
    end

    test "stale idle timeout tokens are ignored" do
      test_pid = self()
      active_token = make_ref()
      stale_token = make_ref()

      :sys.replace_state(AudioPlayer, fn state ->
        %{
          state
          | voice_channel: {"guild-1", "ch-1"},
            idle_timeout_ref: {make_ref(), active_token}
        }
      end)

      with_mock Voice,
        leave_channel: fn _ ->
          send(test_pid, :leave_called)
          :ok
        end do
        send(AudioPlayer, {:idle_timeout, stale_token})
        # Sync, then verify nothing happened
        AudioPlayer.current_voice_channel()
        refute_receive :leave_called, 100

        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == {"guild-1", "ch-1"}
      end
    end
  end

  describe "last_user_left" do
    test "leaves immediately in play mode" do
      test_pid = self()

      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: {"guild-1", "ch-1"}, idle_timeout_ref: nil}
      end)

      with_mock Voice,
        leave_channel: fn "guild-1" ->
          send(test_pid, :leave_called)
          :ok
        end do
        AudioPlayer.last_user_left("guild-1")
        assert_receive :leave_called, 1_000

        AudioPlayer.current_voice_channel()
        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == nil
        assert state.idle_timeout_ref == nil
      end
    end

    test "leaves immediately in presence mode" do
      test_pid = self()

      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: {"guild-1", "ch-1"}, idle_timeout_ref: nil}
      end)

      with_mocks([
        {AutoJoinPolicy, [], [mode: fn -> :presence end]},
        {Voice, [],
         [
           leave_channel: fn "guild-1" ->
             send(test_pid, :leave_called)
             :ok
           end
         ]}
      ]) do
        AudioPlayer.last_user_left("guild-1")
        assert_receive :leave_called, 1_000

        AudioPlayer.current_voice_channel()
        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == nil
      end
    end

    test "starts idle timer in false mode (with timeout configured)" do
      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: {"guild-1", "ch-1"}, idle_timeout_ref: nil}
      end)

      with_mocks([
        {AutoJoinPolicy, [], [mode: fn -> false end]},
        {Soundboard.Discord.Handler.IdleTimeoutPolicy, [], [timeout_ms: fn -> 60_000 end]},
        {Voice, [], [leave_channel: fn _ -> :ok end]}
      ]) do
        AudioPlayer.last_user_left("guild-1")
        AudioPlayer.current_voice_channel()

        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == {"guild-1", "ch-1"}
        assert state.idle_timeout_ref != nil
        refute called(Voice.leave_channel(:_))
      end
    end

    test "stays in false mode when timeout is disabled (0)" do
      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: {"guild-1", "ch-1"}, idle_timeout_ref: nil}
      end)

      with_mocks([
        {AutoJoinPolicy, [], [mode: fn -> false end]},
        {Soundboard.Discord.Handler.IdleTimeoutPolicy, [], [timeout_ms: fn -> nil end]},
        {Voice, [], [leave_channel: fn _ -> :ok end]}
      ]) do
        AudioPlayer.last_user_left("guild-1")
        AudioPlayer.current_voice_channel()

        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == {"guild-1", "ch-1"}
        assert state.idle_timeout_ref == nil
        refute called(Voice.leave_channel(:_))
      end
    end

    test "ignores last_user_left when bot is not in a channel" do
      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: nil}
      end)

      with_mock Voice, leave_channel: fn _ -> :ok end do
        AudioPlayer.last_user_left("guild-1")
        AudioPlayer.current_voice_channel()

        refute called(Voice.leave_channel(:_))
      end
    end
  end

  describe "user_joined_channel" do
    test "cancels idle timer" do
      token = make_ref()

      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: {"guild-1", "ch-1"}, idle_timeout_ref: {make_ref(), token}}
      end)

      AudioPlayer.user_joined_channel("guild-1")
      AudioPlayer.current_voice_channel()

      state = :sys.get_state(AudioPlayer)
      assert state.idle_timeout_ref == nil
    end
  end

  describe "auto-join on play" do
    test "auto-joins user's voice channel when bot has no channel and actor has discord_id" do
      test_pid = self()
      user = %User{discord_id: "discord-99", username: "tester", id: 1}

      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: nil, idle_timeout_ref: nil}
      end)

      with_mocks([
        {VoicePresence, [],
         [find_user_voice_channel: fn "discord-99" -> {:ok, {"guild-1", "ch-5"}} end]},
        {Voice, [],
         [
           join_channel: fn "guild-1", "ch-5" ->
             send(test_pid, :join_called)
             :ok
           end
         ]},
        {Soundboard.AudioPlayer.SoundLibrary, [],
         [get_sound_path: fn _ -> {:error, "not found"} end]}
      ]) do
        AudioPlayer.play_sound("any.mp3", user)
        assert_receive :join_called, 1_000

        AudioPlayer.current_voice_channel()
        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == {"guild-1", "ch-5"}
        assert state.idle_timeout_ref != nil
      end
    end

    test "shows error and skips auto-join when user is not in any voice channel" do
      user = %User{discord_id: "discord-99", username: "tester", id: 1}

      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: nil, idle_timeout_ref: nil}
      end)

      with_mocks([
        {VoicePresence, [], [find_user_voice_channel: fn "discord-99" -> :not_found end]},
        {Voice, [], [join_channel: fn _, _ -> :ok end]}
      ]) do
        AudioPlayer.play_sound("any.mp3", user)
        AudioPlayer.current_voice_channel()

        state = :sys.get_state(AudioPlayer)
        assert state.voice_channel == nil

        refute called(Voice.join_channel(:_, :_))
      end
    end

    test "skips auto-join for actors without discord_id" do
      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: nil, idle_timeout_ref: nil}
      end)

      with_mocks([
        {VoicePresence, [], [find_user_voice_channel: fn _ -> {:ok, {"guild-1", "ch-1"}} end]},
        {Voice, [], [join_channel: fn _, _ -> :ok end]}
      ]) do
        AudioPlayer.play_sound("any.mp3", "System")
        AudioPlayer.current_voice_channel()

        refute called(VoicePresence.find_user_voice_channel(:_))
        refute called(Voice.join_channel(:_, :_))
      end
    end

    test "skips auto-join in false mode" do
      user = %User{discord_id: "discord-99", username: "tester", id: 1}

      :sys.replace_state(AudioPlayer, fn state ->
        %{state | voice_channel: nil, idle_timeout_ref: nil}
      end)

      with_mocks([
        {AutoJoinPolicy, [], [mode: fn -> false end]},
        {VoicePresence, [], [find_user_voice_channel: fn _ -> {:ok, {"guild-1", "ch-1"}} end]},
        {Voice, [], [join_channel: fn _, _ -> :ok end]}
      ]) do
        AudioPlayer.play_sound("any.mp3", user)
        AudioPlayer.current_voice_channel()

        refute called(VoicePresence.find_user_voice_channel(:_))
        refute called(Voice.join_channel(:_, :_))
      end
    end
  end
end
