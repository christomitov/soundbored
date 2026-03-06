defmodule SoundboardWeb.AudioPlayerTest do
  use ExUnit.Case, async: false

  import Mock

  alias SoundboardWeb.AudioPlayer
  alias SoundboardWeb.AudioPlayer.State

  setup do
    original_state = :sys.get_state(AudioPlayer)

    on_exit(fn ->
      :sys.replace_state(AudioPlayer, fn _ -> original_state end)
    end)

    :ok
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

    with_mock Soundboard.Discord.Voice,
      channel_id: fn "guild-1" -> "channel-1" end,
      ready?: fn "guild-1" -> false end,
      playing?: fn "guild-1" -> raise "playback status unavailable" end,
      join_channel: fn "guild-1", "channel-1" ->
        send(test_pid, :join_attempted)
        :ok
      end do
      send(AudioPlayer, :check_voice_connection)

      assert_receive :join_attempted
    end
  end
end
