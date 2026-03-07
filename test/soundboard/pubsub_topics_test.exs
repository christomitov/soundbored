defmodule Soundboard.PubSubTopicsTest do
  use ExUnit.Case, async: false

  alias Soundboard.PubSubTopics

  test "exposes canonical topic names" do
    assert PubSubTopics.files_topic() == "soundboard.files"
    assert PubSubTopics.playback_topic() == "soundboard.playback"
    assert PubSubTopics.stats_topic() == "soundboard.stats"
  end

  test "broadcast helpers publish to subscribed topics" do
    PubSubTopics.subscribe_files()
    PubSubTopics.subscribe_playback()
    PubSubTopics.subscribe_stats()

    assert :ok = PubSubTopics.broadcast_files_updated()
    assert_receive {:files_updated}

    assert :ok = PubSubTopics.broadcast_sound_played("wow.mp3", "tester")
    assert_receive {:sound_played, %{filename: "wow.mp3", played_by: "tester"}}

    assert :ok = PubSubTopics.broadcast_error("boom")
    assert_receive {:error, "boom"}

    assert :ok = PubSubTopics.broadcast_stats_updated()
    assert_receive {:stats_updated}
  end
end
