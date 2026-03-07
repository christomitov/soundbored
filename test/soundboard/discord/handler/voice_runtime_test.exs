defmodule Soundboard.Discord.Handler.VoiceRuntimeTest do
  use ExUnit.Case, async: false

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
end
