defmodule Soundboard.Discord.Handler.VoiceRuntimeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Soundboard.Discord.Handler.{AutoJoinPolicy, VoicePresence, VoiceRuntime}

  test "handle_disconnect returns a recheck action instead of scheduling directly" do
    payload = %{guild_id: "guild-1"}

    with_mocks([
      {AutoJoinPolicy, [], [mode: fn -> :enabled end]},
      {VoicePresence, [],
       [
         current_voice_channel: fn -> {:ok, {"guild-1", "channel-1"}} end,
         users_in_channel: fn "guild-1", "channel-1" -> {:ok, 2} end
       ]}
    ]) do
      assert VoiceRuntime.handle_disconnect(payload) == [
               {:schedule_recheck_alone, "guild-1", "channel-1", 1_500}
             ]
    end
  end

  test "handle_connect returns a recheck action when the bot is still sharing another channel" do
    payload = %{guild_id: "guild-1", channel_id: "channel-2", user_id: "user-1"}

    with_mocks([
      {AutoJoinPolicy, [], [mode: fn -> :enabled end]},
      {VoicePresence, [],
       [
         bot_user?: fn "user-1" -> false end,
         current_voice_channel: fn -> {:ok, {"guild-1", "channel-1"}} end,
         users_in_channel: fn "guild-1", "channel-1" -> {:ok, 3} end
       ]}
    ]) do
      assert VoiceRuntime.handle_connect(payload) == [
               {:schedule_recheck_alone, "guild-1", "channel-1", 1_500}
             ]
    end
  end

  test "recheck_alone logs and returns no actions when voice state is unavailable" do
    log =
      capture_log(fn ->
        with_mocks([
          {VoicePresence, [],
           [
             current_voice_channel: fn -> {:ok, {"guild-1", "channel-1"}} end,
             users_in_channel: fn "guild-1", "channel-1" -> {:error, :unavailable} end
           ]}
        ]) do
          assert VoiceRuntime.recheck_alone("guild-1", "channel-1") == []
        end
      end)

    assert log =~ "Recheck skipped because voice state was unavailable"
  end

  test "bootstrap scans cached guilds and joins an active voice channel" do
    test_pid = self()

    guild = %{
      id: "guild-1",
      voice_states: [
        %{user_id: "user-1", channel_id: nil},
        %{user_id: "user-2", channel_id: "channel-9"}
      ]
    }

    with_mocks([
      {AutoJoinPolicy, [], [mode: fn -> :enabled end]},
      {VoicePresence, [],
       [cached_guilds: fn -> {:ok, [guild]} end, bot_id: fn -> {:ok, "bot-1"} end]},
      {Soundboard.Discord.Voice, [],
       [join_channel: fn "guild-1", "channel-9" -> send(test_pid, :joined_bootstrap_channel) end]},
      {Soundboard.AudioPlayer, [],
       [set_voice_channel: fn "guild-1", "channel-9" -> send(test_pid, :set_bootstrap_voice) end]}
    ]) do
      assert :ok = VoiceRuntime.bootstrap()
      assert_receive :joined_bootstrap_channel, 6_000
      assert_receive :set_bootstrap_voice, 1_000
    end
  end
end
