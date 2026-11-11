defmodule Soundboard.AudioPlayer.GuildsTest do
  @moduledoc """
  Per-guild playback: each tenant gets its own player process and its own
  playback state, and one guild's activity never touches another's. The
  default-guild path keeps single-guild deployments unchanged.
  """

  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Soundboard.{AudioPlayer, PubSubTopics, Tenants}

  setup do
    suffix = System.unique_integer([:positive])
    guilds = %{a: "guild-a-#{suffix}", b: "guild-b-#{suffix}"}

    on_exit(fn ->
      for guild <- [Tenants.default_guild_id() | Map.values(guilds)] do
        stop_player(guild)
      end
    end)

    guilds
  end

  test "each guild gets its own player process", %{a: a, b: b} do
    pid_a = AudioPlayer.ensure_started(a)
    pid_b = AudioPlayer.ensure_started(b)

    assert pid_a != pid_b
    assert AudioPlayer.ensure_started(a) == pid_a
    assert AudioPlayer.server_pid(a) == pid_a
    assert AudioPlayer.server_pid(b) == pid_b
  end

  test "playing without a guild targets the default guild" do
    default_guild = Tenants.default_guild_id()
    stop_player(default_guild)
    PubSubTopics.subscribe_playback(default_guild)

    AudioPlayer.play_sound("whatever.mp3", "System")

    assert_receive {:error,
                    "Bot is not connected to a voice channel. Use !join in Discord first."}

    assert AudioPlayer.server_pid(default_guild)
  end

  test "voice channel state is isolated per guild", %{a: a, b: b} do
    AudioPlayer.set_voice_channel(a, "ch-a")
    AudioPlayer.set_voice_channel(b, "ch-b")

    assert {:ok, {a, "ch-a"}} == AudioPlayer.current_voice_channel(a)
    assert {:ok, {b, "ch-b"}} == AudioPlayer.current_voice_channel(b)

    AudioPlayer.last_user_left(b)

    assert {:ok, {a, "ch-a"}} == AudioPlayer.current_voice_channel(a)
    assert {:ok, nil} == AudioPlayer.current_voice_channel(b)
  end

  test "playback events for one guild do not appear on another guild's topic", %{a: a, b: b} do
    PubSubTopics.subscribe_playback(a)

    PubSubTopics.broadcast_sound_played("x.mp3", "someone", b)
    PubSubTopics.broadcast_sound_played("y.mp3", "someone", a)

    assert_receive {:sound_played, %{filename: "y.mp3"}}
    refute_received {:sound_played, %{filename: "x.mp3"}}
  end

  defp stop_player(guild) do
    if pid = AudioPlayer.server_pid(guild), do: GenServer.stop(pid)
  end
end
