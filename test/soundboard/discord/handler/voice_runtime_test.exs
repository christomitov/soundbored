defmodule Soundboard.Discord.Handler.VoiceRuntimeTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Mock

  alias Soundboard.{AudioPlayer, FakeVoice}
  alias Soundboard.Discord.BotIdentity
  alias Soundboard.Discord.Handler.{VoicePresence, VoiceRuntime}

  @channel "channel-1"

  setup do
    guild = "runtime-#{System.unique_integer([:positive])}"
    Application.put_env(:soundboard, :bot_ready, true)

    on_exit(fn ->
      System.delete_env("AUTO_JOIN")
      Application.delete_env(:soundboard, :bot_ready)
      if pid = AudioPlayer.server_pid(guild), do: GenServer.stop(pid)
    end)

    %{guild: guild}
  end

  test "handle_disconnect schedules a recheck while other users remain", %{guild: guild} do
    payload = %{guild_id: guild, user_id: "user-1"}

    with_mocks(presence(guild, 2)) do
      assert VoiceRuntime.handle_disconnect(payload) == [
               {:schedule_recheck_alone, guild, @channel, 1_500}
             ]
    end
  end

  test "handle_connect in presence mode rechecks the channel the bot still shares",
       %{guild: guild} do
    auto_join(:presence)
    payload = %{guild_id: guild, channel_id: "channel-2", user_id: "user-1"}

    with_mocks(presence(guild, 3)) do
      assert VoiceRuntime.handle_connect(payload) == [
               {:schedule_recheck_alone, guild, @channel, 1_500}
             ]
    end
  end

  test "the bot leaves once it is alone, in every mode that leaves", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel)
    payload = %{guild_id: guild, user_id: "user-1"}

    for mode <- [:play, :presence] do
      auto_join(mode)
      AudioPlayer.set_voice_channel(guild, @channel)

      with_mocks(presence(guild, 0)) do
        assert VoiceRuntime.handle_disconnect(payload) == []
      end

      assert_receive {:fake_voice, ^guild, :leave}, 500, "#{mode} mode did not leave"
      assert AudioPlayer.current_voice_channel(guild) == {:ok, nil}
    end
  end

  test "in false mode the bot stays when it is left alone", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel)
    auto_join(false)
    AudioPlayer.set_voice_channel(guild, @channel)

    with_mocks(presence(guild, 0)) do
      assert VoiceRuntime.handle_disconnect(%{guild_id: guild, user_id: "user-1"}) == []
    end

    assert AudioPlayer.current_voice_channel(guild) == {:ok, {guild, @channel}}
    refute_received {:fake_voice, ^guild, :leave}
  end

  test "presence mode leaves when a user moves away and the bot is alone", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel)
    auto_join(:presence)
    AudioPlayer.set_voice_channel(guild, @channel)
    payload = %{guild_id: guild, channel_id: "channel-2", user_id: "user-1"}

    with_mocks(presence(guild, 0)) do
      assert VoiceRuntime.handle_connect(payload) == []
    end

    assert_receive {:fake_voice, ^guild, :leave}
    assert AudioPlayer.current_voice_channel(guild) == {:ok, nil}
  end

  test "recheck_alone leaves only when the channel is confirmed empty", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel)
    AudioPlayer.set_voice_channel(guild, @channel)

    for users <- [2, {:error, :unavailable}] do
      with_mocks(presence(guild, users)) do
        assert VoiceRuntime.recheck_alone(guild, @channel) == []
      end

      assert AudioPlayer.current_voice_channel(guild) == {:ok, {guild, @channel}}
      refute_received {:fake_voice, ^guild, :leave}
    end

    with_mocks(presence(guild, 0)) do
      assert VoiceRuntime.recheck_alone(guild, @channel) == []
    end

    assert_receive {:fake_voice, ^guild, :leave}
    assert AudioPlayer.current_voice_channel(guild) == {:ok, nil}
  end

  test "bootstrap in presence mode joins a cached channel that has users", %{guild: guild} do
    auto_join(:presence)
    FakeVoice.claim(guild)

    cached = %{
      id: guild,
      voice_states: [
        %{user_id: "bot-1", channel_id: "bot-channel"},
        %{user_id: "user-1", channel_id: nil},
        %{user_id: "user-2", channel_id: "channel-9"}
      ]
    }

    with_mock VoicePresence, [:passthrough],
      cached_guilds: fn -> {:ok, [cached]} end,
      bot_id: fn -> {:ok, "bot-1"} end do
      assert :ok = VoiceRuntime.bootstrap()
      assert_receive {:fake_voice, ^guild, {:join, "channel-9"}}, 6_000
    end
  end

  test "handle_connect in false mode cancels the idle timer only for the bot's channel",
       %{guild: guild} do
    auto_join(false)
    AudioPlayer.set_voice_channel(guild, @channel)
    AudioPlayer.last_user_left(guild)
    assert armed?(guild)

    with_mocks(presence(guild, 1)) do
      VoiceRuntime.handle_connect(%{guild_id: guild, channel_id: "channel-2", user_id: "u"})
      assert armed?(guild)

      VoiceRuntime.handle_connect(%{guild_id: guild, channel_id: @channel, user_id: "u"})
      refute armed?(guild)
    end
  end

  test "handle_disconnect ignores the bot's own voice disconnect", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel)
    AudioPlayer.set_voice_channel(guild, @channel)

    with_mocks(presence(guild, 0, true)) do
      assert VoiceRuntime.handle_disconnect(%{guild_id: guild, user_id: "bot-1"}) == []
    end

    assert AudioPlayer.current_voice_channel(guild) == {:ok, {guild, @channel}}
    refute_received {:fake_voice, ^guild, :leave}
  end

  defp presence(guild, users, bot? \\ false) do
    [
      {VoicePresence, [:passthrough],
       [
         bot_user?: fn _ -> bot? end,
         current_voice_channel: fn ^guild -> {:ok, {guild, @channel}} end,
         users_in_channel: fn ^guild, _channel ->
           if is_integer(users), do: {:ok, users}, else: users
         end
       ]},
      {BotIdentity, [], [fetch: fn -> {:ok, %{id: "bot-1"}} end]}
    ]
  end

  defp auto_join(:play), do: System.delete_env("AUTO_JOIN")
  defp auto_join(mode), do: System.put_env("AUTO_JOIN", to_string(mode))

  defp armed?(guild), do: :sys.get_state(AudioPlayer.server_pid(guild)).idle_timeout_ref != nil
end
