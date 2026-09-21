defmodule Soundboard.YouTube.ExtractorTest do
  use ExUnit.Case, async: false

  alias Soundboard.YouTube.Extractor

  setup do
    previous = Application.get_env(:soundboard, :ytdlp_cmd)
    previous_exe = Application.get_env(:soundboard, :ytdlp_executable)
    previous_cookies_path = Application.get_env(:soundboard, :youtube_cookies_path)

    cookies_path =
      Path.join(
        System.tmp_dir!(),
        "yt-extractor-cookies-#{System.unique_integer([:positive])}.txt"
      )

    Application.put_env(:soundboard, :youtube_cookies_path, cookies_path)

    on_exit(fn ->
      restore_env(:ytdlp_cmd, previous)
      restore_env(:ytdlp_executable, previous_exe)
      restore_env(:youtube_cookies_path, previous_cookies_path)
      File.rm(cookies_path)
    end)

    %{cookies_path: cookies_path}
  end

  test "valid_url?/1 accepts common youtube forms" do
    assert Extractor.valid_url?("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert Extractor.valid_url?("https://youtu.be/dQw4w9WgXcQ")
    assert Extractor.valid_url?("https://www.youtube.com/shorts/dQw4w9WgXcQ")
    refute Extractor.valid_url?("https://example.com/watch?v=dQw4w9WgXcQ")
    refute Extractor.valid_url?("not a url")
  end

  test "youtube_id/1 extracts ids" do
    assert {:ok, "dQw4w9WgXcQ"} =
             Extractor.youtube_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30")

    assert {:error, _} = Extractor.youtube_id("https://vimeo.com/123")
  end

  test "start_offset_ms/1 parses youtube timestamps" do
    assert Extractor.start_offset_ms("https://www.youtube.com/watch?v=XCA9SOcdA9M") == 0

    assert Extractor.start_offset_ms("https://www.youtube.com/watch?v=XCA9SOcdA9M&t=5s") ==
             5_000

    assert Extractor.start_offset_ms("https://www.youtube.com/watch?v=XCA9SOcdA9M&t=5") ==
             5_000

    assert Extractor.start_offset_ms("https://youtu.be/XCA9SOcdA9M?t=1m30s") == 90_000

    assert Extractor.start_offset_ms("https://www.youtube.com/watch?v=XCA9SOcdA9M&t=1h2m3s") ==
             3_723_000

    assert Extractor.start_offset_ms("https://www.youtube.com/embed/XCA9SOcdA9M?start=12") ==
             12_000

    assert Extractor.start_offset_ms("https://www.youtube.com/watch?v=XCA9SOcdA9M#t=45s") ==
             45_000
  end

  test "probe/1 returns metadata without downloading" do
    Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")

    Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
      if "--skip-download" in args do
        {"Probe Title\n42\nnot_live\nhttps://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg\n", 0}
      else
        {"should not download", 1}
      end
    end)

    assert {:ok, meta} = Extractor.probe("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert meta.title == "Probe Title"
    assert meta.duration_ms == 42_000
    assert meta.youtube_id == "dQw4w9WgXcQ"

    assert meta.thumbnail_url ==
             "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"

    refute meta.live?
  end

  test "uses the saved cookies for metadata and media requests", %{cookies_path: cookies_path} do
    Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")
    File.write!(cookies_path, ".youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN_INFO\ttest\n")

    parent = self()

    Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
      send(parent, {:ytdlp_args, args})

      if "--skip-download" in args do
        {"Cookie Test\n42\nnot_live\n", 0}
      else
        output_template = Enum.at(args, Enum.find_index(args, &(&1 == "-o")) + 1)
        File.write!(String.replace(output_template, "%(ext)s", "mp4"), "fake")
        {"", 0}
      end
    end)

    dir = Path.join(System.tmp_dir!(), "yt-cookie-extract-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    assert {:ok, _extraction} =
             Extractor.download("https://www.youtube.com/watch?v=dQw4w9WgXcQ", dir)

    assert_receive {:ytdlp_args, metadata_args}
    assert_receive {:ytdlp_args, media_args}

    for args <- [metadata_args, media_args] do
      cookie_index = Enum.find_index(args, &(&1 == "--cookies"))
      assert is_integer(cookie_index)
      assert Enum.at(args, cookie_index + 1) == cookies_path
      assert List.last(args) == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    end
  end

  test "download/2 downloads when metadata and media succeed" do
    Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")

    dir = Path.join(System.tmp_dir!(), "yt-extract-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    media_path = Path.join(dir, "dQw4w9WgXcQ.mp4")
    File.write!(media_path, "fake")

    Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
      if "--skip-download" in args do
        {"Long Video\n9999\nnot_live\n", 0}
      else
        assert "bv*[height<=720]+ba/b[height<=720]" in args
        {"", 0}
      end
    end)

    assert {:ok, extraction} =
             Extractor.download("https://www.youtube.com/watch?v=dQw4w9WgXcQ", dir)

    assert extraction.title == "Long Video"
    assert extraction.duration_ms == 9_999_000
    assert extraction.media_path == media_path

    assert extraction.thumbnail_url ==
             "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "yt-extract-*"))
  end

  test "download/2 returns friendly error when yt-dlp fails" do
    Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")

    Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
      if "--skip-download" in args do
        {"Title\n120\nnot_live\n", 0}
      else
        {"ERROR: Sign in to confirm your age", 1}
      end
    end)

    dir = Path.join(System.tmp_dir!(), "yt-extract-#{System.unique_integer([:positive])}")

    assert {:error, message} =
             Extractor.download("https://www.youtube.com/watch?v=dQw4w9WgXcQ", dir)

    assert message =~ "age-restricted" or message =~ "cookies"
  end

  test "reports when YouTube rejects cookies that were actually supplied", %{
    cookies_path: cookies_path
  } do
    Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")
    File.write!(cookies_path, ".youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN_INFO\tstale\n")

    Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
      assert "--cookies" in args
      assert cookies_path in args
      {"ERROR: Sign in to confirm you're not a bot", 1}
    end)

    dir = Path.join(System.tmp_dir!(), "yt-extract-#{System.unique_integer([:positive])}")

    assert {:error, message} =
             Extractor.download("https://www.youtube.com/watch?v=dQw4w9WgXcQ", dir)

    assert message =~ "rejected the saved cookies"
    assert message =~ "replace the cookies"
  end

  test "download/2 returns friendly error when formats missing without JS runtime" do
    Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")

    Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
      if "--skip-download" in args do
        {"Title\n120\nnot_live\n", 0}
      else
        {"ERROR: [youtube] abc: Requested format is not available", 1}
      end
    end)

    dir = Path.join(System.tmp_dir!(), "yt-extract-#{System.unique_integer([:positive])}")

    assert {:error, message} =
             Extractor.download("https://www.youtube.com/watch?v=dQw4w9WgXcQ", dir)

    assert message =~ "playable formats" or message =~ "Node.js"
  end

  test "download/2 rejects upcoming live streams" do
    Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")

    Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
      if "--skip-download" in args do
        {"Soon\nNA\nis_upcoming\n", 0}
      else
        {"", 0}
      end
    end)

    dir = Path.join(System.tmp_dir!(), "yt-extract-#{System.unique_integer([:positive])}")

    assert {:error, message} =
             Extractor.download("https://www.youtube.com/watch?v=dQw4w9WgXcQ", dir)

    assert message =~ "hasn't started"
  end

  test "download/2 resolves live stream urls without downloading VOD" do
    Application.put_env(:soundboard, :ytdlp_executable, "/usr/bin/yt-dlp")

    Application.put_env(:soundboard, :ytdlp_cmd, fn _exe, args, _opts ->
      cond do
        "--skip-download" in args ->
          {"Live Show\n3600\nis_live\n", 0}

        "-g" in args ->
          assert "b[height<=720]/bv*[height<=720]+ba/b" in args
          {"https://example.com/live.m3u8\n", 0}

        true ->
          {"unexpected", 1}
      end
    end)

    dir = Path.join(System.tmp_dir!(), "yt-extract-#{System.unique_integer([:positive])}")

    assert {:ok, extraction} =
             Extractor.download("https://www.youtube.com/watch?v=dQw4w9WgXcQ", dir)

    assert extraction.live?
    assert extraction.stream_url == "https://example.com/live.m3u8"
    assert extraction.media_path == nil
    assert extraction.duration_ms == 3_600_000
  end

  test "available?/0 is false when executable disabled" do
    Application.put_env(:soundboard, :ytdlp_executable, false)
    refute Extractor.available?()
  end

  defp restore_env(key, nil), do: Application.delete_env(:soundboard, key)
  defp restore_env(key, value), do: Application.put_env(:soundboard, key, value)
end
