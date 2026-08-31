defmodule Soundboard.AudioPlayer.GuildsTest do
  @moduledoc """
  Behavioral tests for per-guild playback: each tenant gets its own player
  process and its own playback state, and one guild's activity never touches
  another's. The default-guild path keeps single-guild deployments unchanged.
  """

  use Soundboard.DataCase, async: false

  import Mock

  alias Soundboard.AudioPlayer
  alias Soundboard.Tenants

  @default_guild Tenants.default_guild_id()

  setup do
    on_exit(fn ->
      for guild <- [@default_guild, "guild-a", "guild-b"] do
        if pid = AudioPlayer.server_pid(guild) do
          GenServer.stop(pid, :normal)
        end
      end
    end)

    :ok
  end

  test "each guild gets its own player process" do
    pid_a = AudioPlayer.ensure_started("guild-a")
    pid_b = AudioPlayer.ensure_started("guild-b")

    assert pid_a != pid_b
    assert AudioPlayer.server_pid("guild-a") == pid_a
    assert AudioPlayer.server_pid("guild-b") == pid_b
  end

  test "ensure_started/1 is idempotent per guild" do
    pid = AudioPlayer.ensure_started("guild-a")
    assert AudioPlayer.ensure_started("guild-a") == pid
  end

  test "a guild that has never played has no player process" do
    refute AudioPlayer.server_pid("never-started-guild")
  end

  test "playing without a guild targets the default guild (back-compat)" do
    AudioPlayer.play_sound("whatever.mp3", "System")
    assert AudioPlayer.server_pid(@default_guild)
  end

  test "voice channel state is isolated per guild" do
    AudioPlayer.set_voice_channel("guild-a", "ch-a")
    AudioPlayer.set_voice_channel("guild-b", "ch-b")

    assert {:ok, {"guild-a", "ch-a"}} == AudioPlayer.current_voice_channel("guild-a")
    assert {:ok, {"guild-b", "ch-b"}} == AudioPlayer.current_voice_channel("guild-b")
  end

  test "playback_finished/last_user_left events route to the right guild" do
    AudioPlayer.set_voice_channel("guild-a", "ch-a")
    AudioPlayer.set_voice_channel("guild-b", "ch-b")

    AudioPlayer.playback_finished("guild-a")
    AudioPlayer.last_user_left("guild-b")

    # guild-a still in its channel; guild-b left after last user
    assert {:ok, {"guild-a", "ch-a"}} == AudioPlayer.current_voice_channel("guild-a")
    assert {:ok, nil} == AudioPlayer.current_voice_channel("guild-b")
  end

  test "stop_sound/1 stops playback in the given guild only" do
    AudioPlayer.set_voice_channel("guild-a", "ch-a")
    AudioPlayer.set_voice_channel("guild-b", "ch-b")

    test_pid = self()

    with_mocks([
      {Soundboard.Discord.Voice, [], [stop: fn guild -> send(test_pid, {:stopped, guild}) end]},
      {Soundboard.PubSubTopics, [], [broadcast_sound_played: fn _, _, _ -> :ok end]}
    ]) do
      AudioPlayer.stop_sound("guild-a")
      assert_receive {:stopped, "guild-a"}, 1_000
      refute_received {:stopped, "guild-b"}
    end
  end

  test "playback events for one guild do not appear on another guild's topic" do
    # The default guild keeps the base topic; other guilds get a suffixed one.
    assert Soundboard.PubSubTopics.playback_topic(nil) == "soundboard.playback"
    assert Soundboard.PubSubTopics.playback_topic(@default_guild) == "soundboard.playback"
    assert Soundboard.PubSubTopics.playback_topic("guild-z") == "soundboard.playback:guild-z"

    # Subscribing to guild A's topic must not receive guild B's broadcast.
    Phoenix.PubSub.subscribe(Soundboard.PubSub, Soundboard.PubSubTopics.playback_topic("guild-a"))
    Soundboard.PubSubTopics.broadcast_sound_played("x.mp3", "someone", "guild-b")
    refute_received {:sound_played, _}

    Soundboard.PubSubTopics.broadcast_sound_played("y.mp3", "someone", "guild-a")
    assert_received {:sound_played, %{filename: "y.mp3"}}
  end

  test "sound cache is keyed per guild: same filename resolves per-tenant" do
    alias Soundboard.AudioPlayer.SoundLibrary

    SoundLibrary.invalidate_cache("guild-a", "cache-check.mp3")
    SoundLibrary.invalidate_cache("guild-b", "cache-check.mp3")

    # No sounds exist in either guild (DataCase not used; direct ETS checks).
    assert {:error, "Sound not found"} = SoundLibrary.get_sound_path("guild-a", "cache-check.mp3")

    # A cached entry for guild A must not be visible to guild B.
    SoundLibrary.ensure_cache()

    :ets.insert(
      :sound_meta_cache,
      {{"guild-a", "shared.mp3"},
       %{source_type: "url", input: "https://a.example/x.mp3", volume: 1.0}}
    )

    assert {:ok, {"https://a.example/x.mp3", 1.0}} =
             SoundLibrary.get_sound_path("guild-a", "shared.mp3")

    assert {:error, "Sound not found"} = SoundLibrary.get_sound_path("guild-b", "shared.mp3")
  end
end
