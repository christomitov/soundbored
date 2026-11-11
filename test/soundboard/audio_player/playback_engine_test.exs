defmodule Soundboard.AudioPlayer.PlaybackEngineTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Soundboard.{AudioPlayer, FakeVoice, PubSubTopics}
  alias Soundboard.AudioPlayer.PlaybackEngine

  @channel "channel-9"
  @url "https://sounds.example/intro.mp3"

  setup do
    guild = "engine-#{System.unique_integer([:positive])}"
    PubSubTopics.subscribe_playback(guild)

    on_exit(fn ->
      if pid = AudioPlayer.server_pid(guild), do: GenServer.stop(pid)
    end)

    %{guild: guild}
  end

  test "joins the requested channel, then plays and announces the sound", %{guild: guild} do
    FakeVoice.claim(guild)

    assert :ok = play(guild, 0.8)

    assert voice_calls(guild) == [{:join, @channel}, {:play, @url, :url, [volume: 0.8]}]
    assert_received {:sound_played, %{filename: "intro.mp3", played_by: "System"}}
  end

  test "stops audio that is already playing and plays again", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel, playing: true)

    assert :ok = play(guild, 1.0)

    played = {:play, @url, :url, [volume: 1.0]}
    assert voice_calls(guild) == [played, :stop, played]
  end

  test "rejoins the player's channel when the voice session has gone stale", %{guild: guild} do
    AudioPlayer.set_voice_channel(guild, @channel)
    FakeVoice.claim(guild, channel: @channel, play: [{:error, :not_connected}])

    assert :ok = play(guild, 1.0)

    played = {:play, @url, :url, [volume: 1.0]}
    assert voice_calls(guild) == [played, played, played, played, {:join, @channel}, played]
    assert_received {:sound_played, %{filename: "intro.mp3"}}
  end

  test "a play refused while the session connects is retried once VOICE_READY arrives",
       %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel, ready: false)
    test_pid = self()

    engine =
      Task.async(fn ->
        result = play(guild, 1.0)
        send(test_pid, {:engine_done, result})
      end)

    assert_receive {:fake_voice, ^guild, {:play, @url, :url, _}}, 2_000
    FakeVoice.voice_ready(guild)
    Task.await(engine)

    assert_received {:engine_done, :ok}
    assert voice_calls(guild) == [{:play, @url, :url, [volume: 1.0]}]
  end

  test "still plays when EDA does not answer the readiness check", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel, exit_on: [:ready?])

    assert :ok = play(guild, 1.0)

    assert voice_calls(guild) == [{:play, @url, :url, [volume: 1.0]}]
  end

  test "gives up and reports an error when audio never stops", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel, playing: true, stop: :ignored)

    assert :error = play(guild, 1.0)

    assert Enum.frequencies(voice_calls(guild)) == %{
             {:play, @url, :url, [volume: 1.0]} => 20,
             :stop => 20
           }

    assert_received {:error, "Failed to play sound after multiple attempts"}
    refute_received {:sound_played, _}
  end

  test "clamps the volume sent to voice", %{guild: guild} do
    for {volume, sent} <- [{3.0, 1.5}, {-1, 0.0}, {nil, 1.0}, {0.333333, 0.3333}] do
      FakeVoice.claim(guild, channel: @channel)

      assert :ok = play(guild, volume)

      assert voice_calls(guild) == [{:play, @url, :url, [volume: sent]}]
    end
  end

  defp play(guild, volume),
    do: PlaybackEngine.play(guild, @channel, "intro.mp3", @url, volume, "System")

  defp voice_calls(guild) do
    receive do
      {:fake_voice, ^guild, call} -> [call | voice_calls(guild)]
    after
      0 -> []
    end
  end
end
