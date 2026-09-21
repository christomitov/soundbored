defmodule Soundboard.Video.SessionsPath do
  @moduledoc """
  Storage paths for ephemeral video HLS sessions.
  """

  @default_relative_dir "priv/video_sessions"

  @type path_input :: String.t() | [String.t()]

  def dir do
    Application.get_env(:soundboard, :video_sessions_dir, @default_relative_dir)
    |> expand_dir()
  end

  def session_dir(session_id) when is_binary(session_id) do
    Path.join(dir(), session_id)
  end

  def playlist_path(session_id) when is_binary(session_id) do
    Path.join(session_dir(session_id), "index.m3u8")
  end

  def media_path(session_id, filename \\ "media.mp4")
      when is_binary(session_id) and is_binary(filename) do
    Path.join(session_dir(session_id), filename)
  end

  @spec safe_joined_path(String.t(), path_input()) :: {:ok, String.t()} | :error
  def safe_joined_path(session_id, path) when is_binary(session_id) do
    base_dir = session_dir(session_id) |> Path.expand()

    candidate =
      path
      |> normalize_path_segments()
      |> then(&Path.join([base_dir | &1]))
      |> Path.expand()

    if within_dir?(candidate, base_dir) do
      {:ok, candidate}
    else
      :error
    end
  end

  def cleanup_session(session_id) when is_binary(session_id) do
    session_dir(session_id)
    |> File.rm_rf()
    |> case do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  def ensure_session_dir(session_id) when is_binary(session_id) do
    File.mkdir_p(session_dir(session_id))
  end

  defp normalize_path_segments(path) when is_binary(path), do: [path]
  defp normalize_path_segments(path_segments) when is_list(path_segments), do: path_segments

  defp within_dir?(candidate, base_dir) do
    candidate == base_dir or String.starts_with?(candidate, base_dir <> "/")
  end

  defp expand_dir(path) when is_binary(path) do
    case Path.type(path) do
      :absolute -> path
      _ -> Application.app_dir(:soundboard, path)
    end
  end
end
