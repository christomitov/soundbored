defmodule Soundboard.PubSubTopicsTest do
  use ExUnit.Case, async: false

  alias Soundboard.PubSubTopics

  test "exposes canonical topic names" do
    assert PubSubTopics.files_topic() == "soundboard.files"
    assert PubSubTopics.playback_topic() == "soundboard.playback"
    assert PubSubTopics.stats_topic() == "soundboard.stats"
    assert PubSubTopics.video_topic() == "soundboard.video"
  end

  test "broadcast helpers publish to subscribed topics" do
    PubSubTopics.subscribe_files()
    PubSubTopics.subscribe_playback()
    PubSubTopics.subscribe_stats()
    PubSubTopics.subscribe_video()

    assert :ok = PubSubTopics.broadcast_files_updated()
    assert_receive {:files_updated}

    assert :ok =
             PubSubTopics.broadcast_sound_played("wow.mp3", "tester", %{
               sound_id: 7,
               duration_ms: 1200
             })

    assert_receive {:sound_played,
                    %{
                      filename: "wow.mp3",
                      played_by: "tester",
                      sound_id: 7,
                      duration_ms: 1200,
                      started_at: started_at
                    }}

    assert is_integer(started_at)

    assert :ok = PubSubTopics.broadcast_playback_stopped()
    assert_receive {:playback_stopped}

    assert :ok = PubSubTopics.broadcast_error("boom")
    assert_receive {:error, "boom"}

    assert :ok = PubSubTopics.broadcast_stats_updated()
    assert_receive {:stats_updated}

    assert :ok = PubSubTopics.broadcast_video_state(%{id: "s1", status: :ready})
    assert_receive {:video_state, %{id: "s1", status: :ready}}

    assert :ok = PubSubTopics.broadcast_video_sync(%{position_ms: 100, playing?: true})
    assert_receive {:video_sync, %{position_ms: 100}}

    assert :ok = PubSubTopics.broadcast_video_error("nope")
    assert_receive {:video_error, "nope"}

    assert :ok = PubSubTopics.broadcast_video_stopped()
    assert_receive {:video_stopped}

    assert :ok = PubSubTopics.broadcast_video_queue([%{id: "q1", title: "Next"}])
    assert_receive {:video_queue, [%{id: "q1"}]}
  end
end
