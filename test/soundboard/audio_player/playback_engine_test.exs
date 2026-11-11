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

  test "retries transient voice errors", %{guild: guild} do
    played = {:play, @url, :url, [volume: 1.0]}

    table = [
      {:already_playing, [played, :stop, played]},
      {:not_connected, [played, played]}
    ]

    for {error, calls} <- table do
      FakeVoice.claim(guild, channel: @channel, play: [{:error, error}])

      assert :ok = play(guild, 1.0)

      assert {error, voice_calls(guild)} == {error, calls}
    end
  end

  test "refreshes the voice session after repeated encryption negotiation failures",
       %{guild: guild} do
    AudioPlayer.set_voice_channel(guild, @channel)
    FakeVoice.claim(guild, channel: @channel, play: List.duplicate({:error, :not_ready}, 4))

    assert :ok = play(guild, 1.0)

    played = {:play, @url, :url, [volume: 1.0]}
    assert voice_calls(guild) == [played, played, played, played, {:join, @channel}, played]
  end

  test "still plays when the voice session never reports ready", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel, ready: false)

    assert :ok = play(guild, 1.0)

    assert voice_calls(guild) == [{:play, @url, :url, [volume: 1.0]}]
  end

  test "gives up and reports an error when audio never stops", %{guild: guild} do
    FakeVoice.claim(guild,
      channel: @channel,
      play: List.duplicate({:error, :already_playing}, 20)
    )

    assert :error = play(guild, 1.0)

    assert Enum.frequencies(voice_calls(guild)) == %{
             {:play, @url, :url, [volume: 1.0]} => 20,
             :stop => 20
           }

    assert_received {:error, "Failed to play sound after multiple attempts"}
    refute_received {:sound_played, _}
  end

  test "clamps the volume sent to voice", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel)

    for {volume, sent} <- [{3.0, 1.5}, {-1, 0.0}, {nil, 1.0}, {0.333333, 0.3333}] do
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
