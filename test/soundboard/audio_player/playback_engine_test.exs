defmodule Soundboard.AudioPlayer.PlaybackEngineTest do
  use ExUnit.Case, async: false

  import Mock

  alias Soundboard.AudioPlayer.PlaybackEngine

  setup do
    previous_probe = Application.get_env(:soundboard, :voice_rtp_probe)
    Application.put_env(:soundboard, :voice_rtp_probe, false)

    on_exit(fn ->
      if is_nil(previous_probe) do
        Application.delete_env(:soundboard, :voice_rtp_probe)
      else
        Application.put_env(:soundboard, :voice_rtp_probe, previous_probe)
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
end
