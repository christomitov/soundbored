defmodule Soundboard.VideoPlayer.DiscordAudioTest do
  use ExUnit.Case, async: false
  import Mock

  alias Soundboard.AudioPlayer
  alias Soundboard.Discord.Voice
  alias Soundboard.VideoPlayer.DiscordAudio

  setup do
    previous_exe = Application.get_env(:soundboard, :ffmpeg_executable)
    previous_cmd = Application.get_env(:soundboard, :ffmpeg_cmd)

    on_exit(fn ->
      DiscordAudio.stop()

      if previous_exe do
        Application.put_env(:soundboard, :ffmpeg_executable, previous_exe)
      else
        Application.delete_env(:soundboard, :ffmpeg_executable)
      end

      if previous_cmd do
        Application.put_env(:soundboard, :ffmpeg_cmd, previous_cmd)
      else
        Application.delete_env(:soundboard, :ffmpeg_cmd)
      end
    end)

    :ok
  end

  test "seek extract places -ss after -i for frame-accurate Discord audio" do
    dir = Path.join(System.tmp_dir!(), "sb-discord-seek-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    media = Path.join(dir, "media.mp4")
    File.write!(media, "fake")

    Application.put_env(:soundboard, :ffmpeg_executable, "/usr/bin/ffmpeg")

    parent = self()

    Application.put_env(:soundboard, :ffmpeg_cmd, fn _exe, args, _opts ->
      send(parent, {:ffmpeg_args, args})
      out = Enum.at(args, -1)
      File.write!(out, "aac")
      {"", 0}
    end)

    with_mocks([
      {AudioPlayer, [],
       [
         clear_playback: fn -> :ok end,
         ensure_voice_channel: fn _actor -> {:ok, {"guild-1", "channel-1"}} end,
         current_voice_channel: fn -> {:ok, {"guild-1", "channel-1"}} end,
         clear_now_playing: fn -> :ok end
       ]},
      {Voice, [],
       [
         ready?: fn _ -> true end,
         stop: fn _ -> :ok end,
         play: fn _guild, path, :url, _opts ->
           send(parent, {:voice_play, path})
           :ok
         end
       ]}
    ]) do
      assert :ok = DiscordAudio.play_from(media, 1500, "tester")
    end

    assert_receive {:ffmpeg_args, args}, 500
    i_index = Enum.find_index(args, &(&1 == "-i"))
    ss_index = Enum.find_index(args, &(&1 == "-ss"))
    assert is_integer(i_index) and is_integer(ss_index)
    assert i_index < ss_index

    assert_receive {:voice_play, play_path}, 500
    assert play_path =~ "discord_seek_1500.m4a"

    DiscordAudio.stop()
    File.rm_rf!(dir)
  end

  test "live HLS playlist is passed through to Discord without a FIFO" do
    dir = Path.join(System.tmp_dir!(), "sb-discord-live-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    playlist = Path.join(dir, "index.m3u8")

    File.write!(playlist, """
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-TARGETDURATION:2
    #EXTINF:2.0,
    index0.ts
    """)

    parent = self()

    with_mocks([
      {AudioPlayer, [],
       [
         clear_playback: fn -> :ok end,
         ensure_voice_channel: fn _actor -> {:ok, {"guild-1", "channel-1"}} end,
         current_voice_channel: fn -> {:ok, {"guild-1", "channel-1"}} end,
         clear_now_playing: fn -> :ok end
       ]},
      {Voice, [],
       [
         ready?: fn _ -> true end,
         stop: fn _ -> :ok end,
         play: fn _guild, path, :url, _opts ->
           send(parent, {:voice_play, path})
           :ok
         end
       ]}
    ]) do
      assert :ok = DiscordAudio.play_from(playlist, 0, "tester")
    end

    assert_receive {:voice_play, ^playlist}, 500
    refute File.exists?(Path.join(dir, "discord_live.fifo"))

    DiscordAudio.stop()
    File.rm_rf!(dir)
  end
end
