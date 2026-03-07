defmodule Soundboard.AudioPlayer.PlaybackEngineTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Soundboard.AudioPlayer.PlaybackEngine

  setup do
    previous_probe = Application.get_env(:soundboard, :voice_rtp_probe)
    previous_ffmpeg = Application.get_env(:soundboard, :ffmpeg_executable, :system)

    Application.put_env(:soundboard, :voice_rtp_probe, false)
    Application.put_env(:soundboard, :ffmpeg_executable, "/usr/bin/ffmpeg")

    on_exit(fn ->
      if is_nil(previous_probe) do
        Application.delete_env(:soundboard, :voice_rtp_probe)
      else
        Application.put_env(:soundboard, :voice_rtp_probe, previous_probe)
      end

      case previous_ffmpeg do
        :system -> Application.delete_env(:soundboard, :ffmpeg_executable)
        value -> Application.put_env(:soundboard, :ffmpeg_executable, value)
      end
    end)

    :ok
  end

  test "joins the requested channel before playing" do
    test_pid = self()

    with_mocks([
      {Soundboard.AudioPlayer.SoundLibrary, [],
       [prepare_play_input: fn "intro.mp3", "/tmp/intro.mp3" -> {"/tmp/intro.mp3", :url} end]},
      {Soundboard.Discord.Voice, [],
       [
         channel_id: fn "guild-1" -> nil end,
         join_channel: fn "guild-1", "channel-9" -> send(test_pid, :joined_channel) end,
         ready?: fn "guild-1" -> true end,
         play: fn "guild-1", "/tmp/intro.mp3", :url, [volume: 0.8] ->
           send(test_pid, :played_sound)
           :ok
         end
       ]},
      {Soundboard.PubSubTopics, [],
       [broadcast_sound_played: fn "intro.mp3", "System" -> send(test_pid, :broadcast_played) end]},
      {Soundboard.Stats, [],
       [track_play: fn _sound_name, _user_id -> send(test_pid, :tracked_play) end]}
    ]) do
      assert :ok =
               PlaybackEngine.play(
                 "guild-1",
                 "channel-9",
                 "intro.mp3",
                 "/tmp/intro.mp3",
                 0.8,
                 "System"
               )

      assert_receive :joined_channel
      assert_receive :played_sound
      assert_receive :broadcast_played
      refute_received :tracked_play
    end
  end

  test "retries after stopping already-playing audio" do
    test_pid = self()
    attempt_ref = make_ref()
    Process.put(attempt_ref, 0)

    with_mocks([
      {Soundboard.AudioPlayer.SoundLibrary, [],
       [prepare_play_input: fn "retry.mp3", "/tmp/retry.mp3" -> {"/tmp/retry.mp3", :url} end]},
      {Soundboard.Discord.Voice, [],
       [
         channel_id: fn "guild-1" -> "channel-9" end,
         ready?: fn "guild-1" -> true end,
         stop: fn "guild-1" -> send(test_pid, :stopped_audio) end,
         play: fn "guild-1", "/tmp/retry.mp3", :url, [volume: 1.0] ->
           case Process.get(attempt_ref, 0) do
             0 ->
               Process.put(attempt_ref, 1)
               {:error, "Audio already playing in voice channel."}

             _ ->
               send(test_pid, :played_after_retry)
               :ok
           end
         end
       ]},
      {Soundboard.PubSubTopics, [],
       [broadcast_sound_played: fn "retry.mp3", "System" -> send(test_pid, :broadcast_played) end]},
      {Soundboard.Stats, [],
       [track_play: fn _sound_name, _user_id -> send(test_pid, :tracked_play) end]}
    ]) do
      assert :ok =
               PlaybackEngine.play(
                 "guild-1",
                 "channel-9",
                 "retry.mp3",
                 "/tmp/retry.mp3",
                 1.0,
                 "System"
               )

      assert_receive :stopped_audio
      assert_receive :played_after_retry
      assert_receive :broadcast_played
      refute_received :tracked_play
    end
  end

  test "refreshes the current voice session after repeated encryption negotiation failures" do
    test_pid = self()
    attempt_ref = make_ref()
    ready_ref = make_ref()
    Process.put(attempt_ref, 0)
    Process.put(ready_ref, 0)

    with_mocks([
      {Soundboard.AudioPlayer.SoundLibrary, [],
       [
         prepare_play_input: fn "refresh.mp3", "/tmp/refresh.mp3" ->
           {"/tmp/refresh.mp3", :url}
         end
       ]},
      {Soundboard.AudioPlayer, [],
       [current_voice_channel: fn -> {:ok, {"guild-1", "channel-9"}} end]},
      {Soundboard.Discord.Voice, [],
       [
         channel_id: fn "guild-1" -> "channel-9" end,
         ready?: fn "guild-1" ->
           case Process.get(ready_ref, 0) do
             0 ->
               Process.put(ready_ref, 1)
               true

             1 ->
               Process.put(ready_ref, 2)
               false

             _ ->
               true
           end
         end,
         join_channel: fn "guild-1", "channel-9" -> send(test_pid, :refreshed_voice) end,
         play: fn "guild-1", "/tmp/refresh.mp3", :url, [volume: 1.0] ->
           attempt = Process.get(attempt_ref, 0)
           Process.put(attempt_ref, attempt + 1)

           if attempt < 4 do
             {:error, "Voice session is still negotiating encryption."}
           else
             send(test_pid, :played_after_refresh)
             :ok
           end
         end
       ]},
      {Soundboard.PubSubTopics, [],
       [
         broadcast_sound_played: fn "refresh.mp3", "System" ->
           send(test_pid, :broadcast_played)
         end,
         broadcast_error: fn message -> flunk("unexpected playback error: #{message}") end
       ]},
      {Soundboard.Stats, [],
       [track_play: fn _sound_name, _user_id -> send(test_pid, :tracked_play) end]}
    ]) do
      assert :ok =
               PlaybackEngine.play(
                 "guild-1",
                 "channel-9",
                 "refresh.mp3",
                 "/tmp/refresh.mp3",
                 1.0,
                 "System"
               )

      assert_receive :refreshed_voice
      assert_receive :played_after_refresh
      assert_receive :broadcast_played
      refute_received :tracked_play
    end
  end

  test "returns an error when ffmpeg is unavailable" do
    test_pid = self()
    Application.put_env(:soundboard, :ffmpeg_executable, false)

    with_mocks([
      {Soundboard.Discord.Voice, [],
       [
         channel_id: fn "guild-1" -> "channel-9" end,
         ready?: fn "guild-1" -> true end
       ]},
      {Soundboard.PubSubTopics, [],
       [
         broadcast_error: fn "ffmpeg is not installed on this host" ->
           send(test_pid, :broadcast_error)
         end
       ]}
    ]) do
      assert :error =
               PlaybackEngine.play(
                 "guild-1",
                 "channel-9",
                 "missing-ffmpeg.mp3",
                 "/tmp/missing-ffmpeg.mp3",
                 1.0,
                 "System"
               )

      assert_receive :broadcast_error
    end
  end

  test "logs when voice readiness times out before playback" do
    log =
      capture_log(fn ->
        with_mocks([
          {Soundboard.AudioPlayer.SoundLibrary, [],
           [
             prepare_play_input: fn "timeout.mp3", "/tmp/timeout.mp3" ->
               {"/tmp/timeout.mp3", :url}
             end
           ]},
          {Soundboard.Discord.Voice, [],
           [
             channel_id: fn "guild-1" -> "channel-9" end,
             ready?: fn "guild-1" -> false end,
             play: fn "guild-1", "/tmp/timeout.mp3", :url, [volume: 1.0] -> :ok end
           ]},
          {Soundboard.PubSubTopics, [],
           [
             broadcast_sound_played: fn _, _ -> :ok end,
             broadcast_error: fn _ -> :ok end
           ]},
          {Soundboard.Stats, [], [track_play: fn _, _ -> :ok end]}
        ]) do
          assert :ok =
                   PlaybackEngine.play(
                     "guild-1",
                     "channel-9",
                     "timeout.mp3",
                     "/tmp/timeout.mp3",
                     1.0,
                     "System"
                   )
        end
      end)

    assert log =~ "Timed out waiting for voice readiness in guild guild-1"
  end
end
