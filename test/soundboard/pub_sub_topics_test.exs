defmodule Soundboard.PubSubTopicsTest do
  use ExUnit.Case, async: true

  alias Soundboard.PubSubTopics

  test "builds topics for integer and binary tenant ids" do
    assert PubSubTopics.stats_topic(5) == "stats:5"
    assert PubSubTopics.soundboard_topic("abc") == "soundboard:abc"
  end
end
