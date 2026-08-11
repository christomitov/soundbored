defmodule Soundboard.Video.HlsRemuxTest do
  use ExUnit.Case, async: true

  alias Soundboard.Video.HlsRemux

  test "transcode_args/2 builds browser-compatible h264/aac HLS" do
    args = HlsRemux.transcode_args("/tmp/in.mp4", "/tmp/out/index.m3u8")

    assert "-c:v" in args
    assert "libx264" in args
    assert "yuv420p" in args
    assert "expr:gte(t,n_forced*2)" in args
    assert "-c:a" in args
    assert "aac" in args
  end
end
