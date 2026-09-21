defmodule Soundboard.VideoPlayerTest do
  use ExUnit.Case, async: false

  import Mock

  alias Ecto.Adapters.SQL
  alias Soundboard.Accounts.User
  alias Soundboard.{AudioPlayer, PubSubTopics, Repo, VideoPlayer}
  alias Soundboard.Stats.Play
  alias Soundboard.VideoPlayer.DiscordAudio
  alias Soundboard.YouTube.Extractor

  setup do
    :ok = SQL.Sandbox.checkout(Repo)
    SQL.Sandbox.mode(Repo, {:shared, self()})
    reset_audio_player()

    {:ok, host} =
      %User{}
      |> User.changeset(%{
        username: "host_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "a.jpg"
      })
      |> Repo.insert()

    {:ok, guest} =
      %User{}
      |> User.changeset(%{
        username: "guest_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "b.jpg"
      })
      |> Repo.insert()

    VideoPlayer.stop()
    VideoPlayer.session()

    PubSubTopics.subscribe_video()

    on_exit(fn ->
      reset_audio_player()
      VideoPlayer.stop()
      VideoPlayer.session()
      reset_audio_player()
    end)

    %{host: host, guest: guest}
  end

  test "rejects invalid youtube urls", %{host: host} do
    assert {:error, message} = VideoPlayer.play("https://example.com/x", host)
    assert message =~ "YouTube"
  end

  test "queues a video behind sound playback and starts it when sound becomes idle", %{host: host} do
    url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    mark_sound_playing()

    with_mock Extractor,
      valid_url?: fn ^url -> true end,
      available?: fn -> true end,
      youtube_id: fn ^url -> {:ok, "dQw4w9WgXcQ"} end,
      thumbnail_url: fn "dQw4w9WgXcQ" ->
        "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
      end,
      start_offset_ms: fn ^url -> 0 end,
      probe: fn ^url ->
        receive do
          :finish_prefetch -> {:error, "cancelled"}
        after
          5_000 -> {:error, "timed out"}
        end
      end do
      assert {:ok, :queued} = VideoPlayer.play(url, host)
      assert VideoPlayer.session() == nil

      assert [%{youtube_id: "dQw4w9WgXcQ", title: nil, progress_percent: 10}] =
               VideoPlayer.queue()

      VideoPlayer.sound_playback_idle()

      assert %{youtube_id: "dQw4w9WgXcQ", status: :fetching, playing?: false} =
               VideoPlayer.session()

      assert VideoPlayer.queue() == []

      VideoPlayer.stop()
      Process.sleep(20)
    end
  end

  test "serializes queue preparation and prioritizes the newest waiting video", %{host: host} do
    urls = %{
      "https://www.youtube.com/watch?v=aaaaaaaaaaa" => "aaaaaaaaaaa",
      "https://www.youtube.com/watch?v=bbbbbbbbbbb" => "bbbbbbbbbbb",
      "https://www.youtube.com/watch?v=ccccccccccc" => "ccccccccccc"
    }

    [oldest_url, middle_url, newest_url] = Map.keys(urls) |> Enum.sort()
    test_pid = self()
    mark_sound_playing()

    with_mock Extractor,
      valid_url?: fn url -> Map.has_key?(urls, url) end,
      available?: fn -> true end,
      youtube_id: fn url -> {:ok, Map.fetch!(urls, url)} end,
      thumbnail_url: fn id -> "https://i.ytimg.com/vi/#{id}/hqdefault.jpg" end,
      probe: fn url ->
        send(test_pid, {:probe_started, url, self()})

        receive do
          :finish_prefetch -> {:error, "test complete"}
        end
      end do
      assert {:ok, :queued} = VideoPlayer.play(oldest_url, host)
      assert_receive {:probe_started, ^oldest_url, oldest_pid}

      assert {:ok, :queued} = VideoPlayer.play(middle_url, host)
      assert {:ok, :queued} = VideoPlayer.play(newest_url, host)
      refute_receive {:probe_started, ^middle_url, _}, 50
      refute_receive {:probe_started, ^newest_url, _}, 50

      send(oldest_pid, :finish_prefetch)
      assert_receive {:probe_started, ^newest_url, newest_pid}, 1_000
      refute_receive {:probe_started, ^middle_url, _}, 50

      send(newest_pid, :finish_prefetch)
      assert_receive {:probe_started, ^middle_url, middle_pid}, 1_000
      send(middle_pid, :finish_prefetch)

      VideoPlayer.stop()
      Process.sleep(20)
    end
  end

  test "non-host cannot seek or pause", %{host: host, guest: guest} do
    previous_exe = Application.get_env(:soundboard, :ytdlp_executable)
    previous_cmd = Application.get_env(:soundboard, :ytdlp_cmd)
    previous_ffmpeg = Application.get_env(:soundboard, :ffmpeg_cmd)
    previous_ffmpeg_exe = Application.get_env(:soundboard, :ffmpeg_executable)

    with_mock DiscordAudio,
      play_from: fn _, _, _ -> :ok end,
      stop: fn -> :ok end,
      stop_tracked: fn -> :ok end do
      try do
        assert {:error, "No video is playing"} = VideoPlayer.seek(guest, 1000)
        assert {:error, "No video is playing"} = VideoPlayer.pause(host)

        Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")
        Application.put_env(:soundboard, :ffmpeg_executable, "/usr/bin/ffmpeg")

        Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
          if "--skip-download" in args do
            {"Demo Title\n300\nnot_live\n", 0}
          else
            out =
              Enum.find_value(args, fn
                arg ->
                  if is_binary(arg) and String.contains?(arg, "%(ext)s") do
                    String.replace(arg, "%(ext)s", "mp4")
                  end
              end)

            if out, do: File.write!(out, "fake")
            {"", 0}
          end
        end)

        Application.put_env(:soundboard, :ffmpeg_cmd, fn _exe, args, _opts ->
          playlist = List.last(args)
          File.mkdir_p!(Path.dirname(playlist))
          File.write!(playlist, "#EXTM3U\n")
          {"", 0}
        end)

        assert {:ok, :playing} =
                 VideoPlayer.play("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5s", host)

        assert_receive {:video_state, %{status: :fetching, position_ms: 5000}}, 1_000
        assert_receive {:video_state, %{status: :ready, position_ms: position}}, 10_000
        assert position >= 5000

        assert {:ok, :queued} =
                 VideoPlayer.play("https://www.youtube.com/watch?v=oHg5SJYRHA0", guest)

        assert_receive {:video_queue,
                        [
                          %{
                            youtube_id: "oHg5SJYRHA0",
                            thumbnail_url: "https://i.ytimg.com/vi/oHg5SJYRHA0/hqdefault.jpg"
                          }
                        ]},
                       1_000

        session_before_overlay = VideoPlayer.session()
        queue_ids_before_overlay = Enum.map(VideoPlayer.queue(), & &1.id)

        assert :suspended = VideoPlayer.suspend_discord_audio()
        assert VideoPlayer.session().id == session_before_overlay.id
        assert Enum.map(VideoPlayer.queue(), & &1.id) == queue_ids_before_overlay
        assert :ok = VideoPlayer.resume_discord_audio()
        # A synchronous call ensures the preceding resume cast has completed.
        assert VideoPlayer.session().id == session_before_overlay.id
        assert Enum.map(VideoPlayer.queue(), & &1.id) == queue_ids_before_overlay

        assert {:ok, :queued} =
                 VideoPlayer.play("https://www.youtube.com/watch?v=XCA9SOcdA9M", host)

        [skipped, selected] = VideoPlayer.queue()
        assert skipped.youtube_id == "oHg5SJYRHA0"
        assert selected.youtube_id == "XCA9SOcdA9M"

        assert :ok = VideoPlayer.play_queued(host, selected.id)
        assert VideoPlayer.queue() == []
        assert %{id: selected_id, thumbnail_url: selected_thumbnail} = VideoPlayer.session()
        assert selected_id == selected.id
        assert selected_thumbnail == "https://i.ytimg.com/vi/XCA9SOcdA9M/hqdefault.jpg"
        assert_receive {:video_state, %{id: ^selected_id, status: :ready}}, 10_000

        assert {:error, message} = VideoPlayer.seek(guest, 5_000)
        assert message =~ "host"

        assert :ok = VideoPlayer.seek(host, 5_000)
        assert_receive {:video_sync, %{position_ms: 5000}}, 1_000

        assert :ok = VideoPlayer.pause(host)
        assert_receive {:video_sync, %{playing?: false}}, 1_000

        assert :ok = VideoPlayer.seek(host, 7_000)
        assert_receive {:video_sync, %{position_ms: 7000, playing?: false}}, 1_000
        assert %{position_ms: 7000, playing?: false} = VideoPlayer.session()

        assert :ok = VideoPlayer.resume(host)
        assert_receive {:video_sync, %{playing?: true}}, 1_000

        assert {:ok, :queued} =
                 VideoPlayer.play("https://www.youtube.com/watch?v=9bZkp7q19f0", guest)

        [next] = VideoPlayer.queue()

        # Natural browser completion emits pause immediately before ended. The
        # session-specific ended event must still advance to the queued video.
        assert :ok = VideoPlayer.pause(host)
        VideoPlayer.notify_media_ended("stale-session")
        Process.sleep(20)
        assert %{id: ^selected_id, playing?: false} = VideoPlayer.session()

        VideoPlayer.notify_media_ended(selected_id)
        next_session_id = next.id
        assert_receive {:video_state, %{id: ^next_session_id, status: :ready}}, 10_000
        assert %{id: ^next_session_id, playing?: true} = VideoPlayer.session()
        assert VideoPlayer.queue() == []

        assert %Play{media_type: "youtube", youtube_id: "9bZkp7q19f0"} =
                 Repo.get_by(Play, youtube_id: "9bZkp7q19f0")

        VideoPlayer.stop()
        assert_receive {:video_stopped}, 1_000
        assert VideoPlayer.session() == nil
        assert VideoPlayer.queue() == []
      after
        restore(:ytdlp_executable, previous_exe)
        restore(:ytdlp_cmd, previous_cmd)
        restore(:ffmpeg_cmd, previous_ffmpeg)
        restore(:ffmpeg_executable, previous_ffmpeg_exe)
      end
    end
  end

  defp restore(key, nil), do: Application.delete_env(:soundboard, key)
  defp restore(key, value), do: Application.put_env(:soundboard, key, value)

  defp mark_sound_playing do
    :sys.replace_state(AudioPlayer, fn state ->
      %{
        state
        | voice_channel: nil,
          current_playback: %{guild_id: "guild-1", sound_name: "effect.mp3"},
          pending_request: nil,
          interrupting: false
      }
    end)
  end

  defp reset_audio_player do
    :sys.replace_state(AudioPlayer, fn state ->
      case state.idle_timeout_ref do
        {ref, _token} when is_reference(ref) -> Process.cancel_timer(ref)
        _other -> :ok
      end

      if is_reference(state.interrupt_watchdog_ref),
        do: Process.cancel_timer(state.interrupt_watchdog_ref)

      %{
        state
        | voice_channel: nil,
          current_playback: nil,
          pending_request: nil,
          interrupting: false,
          interrupt_watchdog_ref: nil,
          interrupt_watchdog_attempt: 0,
          idle_timeout_ref: nil
      }
    end)
  end
end
