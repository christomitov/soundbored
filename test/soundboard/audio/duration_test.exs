defmodule Soundboard.Audio.DurationTest do
  use ExUnit.Case, async: true

  alias Soundboard.Audio.Duration

  test "probe_ms/1 returns nil for blank or invalid inputs" do
    assert Duration.probe_ms(nil) == nil
    assert Duration.probe_ms("") == nil
    assert Duration.probe_ms("/tmp/does-not-exist-#{System.unique_integer()}.mp3") == nil
  end
end
