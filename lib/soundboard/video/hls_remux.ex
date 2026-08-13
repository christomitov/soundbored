defmodule Soundboard.Video.HlsRemux do
  @moduledoc """
  Converts downloaded media into browser-compatible VOD HLS playlists with ffmpeg.
  """

  require Logger

  alias Soundboard.Video.SessionsPath

  @type remux_result :: %{
          playlist_path: String.t(),
          mode: :transcode
        }

  @spec remux(String.t(), String.t()) :: {:ok, remux_result()} | {:error, String.t()}
  def remux(media_path, session_id)
      when is_binary(media_path) and is_binary(session_id) do
    if File.regular?(media_path) do
      SessionsPath.ensure_session_dir(session_id)
      playlist = SessionsPath.playlist_path(session_id)

      case remux_transcode(media_path, playlist) do
        :ok -> {:ok, %{playlist_path: playlist, mode: :transcode}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "Media file not found"}
    end
  end

  @spec transcode_args(String.t(), String.t()) :: [String.t()]
  def transcode_args(media_path, playlist_path) do
    [
      "-y",
      "-i",
      media_path,
      "-c:v",
      "libx264",
      "-preset",
      "veryfast",
      "-pix_fmt",
      "yuv420p",
      "-force_key_frames",
      "expr:gte(t,n_forced*2)",
      "-c:a",
      "aac",
      "-ac",
      "2",
      "-f",
      "hls",
      "-hls_time",
      "2",
      "-hls_list_size",
      "0",
      "-hls_playlist_type",
      "vod",
      playlist_path
    ]
  end

  defp remux_transcode(media_path, playlist_path) do
    run_ffmpeg(transcode_args(media_path, playlist_path), playlist_path)
  end

  defp run_ffmpeg(args, playlist_path) do
    case Soundboard.SystemCmd.configured_executable(:ffmpeg_executable, "ffmpeg") do
      nil ->
        {:error, "ffmpeg is not installed on this host"}

      exe ->
        run_ffmpeg_command(exe, args, playlist_path)
    end
  end

  defp run_ffmpeg_command(exe, args, playlist_path) do
    timeout = Application.get_env(:soundboard, :ffmpeg_hls_timeout_ms, 300_000)

    case cmd().(exe, args, stderr_to_stdout: true, timeout: timeout) do
      {_, 0} -> verify_playlist(playlist_path)
      {output, code} -> ffmpeg_error(output, code)
    end
  end

  defp verify_playlist(path) do
    if File.regular?(path),
      do: :ok,
      else: {:error, "ffmpeg finished but HLS playlist was not created"}
  end

  defp ffmpeg_error(output, code) do
    Logger.warning("ffmpeg HLS remux failed (#{code}): #{String.slice(output, 0, 500)}")
    {:error, "ffmpeg remux failed (exit #{code})"}
  end

  defp cmd do
    Application.get_env(:soundboard, :ffmpeg_cmd, &Soundboard.SystemCmd.run/3)
  end
end
