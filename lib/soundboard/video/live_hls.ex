defmodule Soundboard.Video.LiveHls do
  @moduledoc """
  Continuously remuxes a live source URL into a sliding-window HLS playlist.
  """

  require Logger

  alias Soundboard.Video.SessionsPath

  @type live_result :: %{
          playlist_path: String.t(),
          mode: :live,
          holder_pid: pid()
        }

  @spec start(String.t(), String.t(), keyword()) :: {:ok, live_result()} | {:error, String.t()}
  def start(stream_url, session_id, opts \\ [])
      when is_binary(stream_url) and is_binary(session_id) do
    case Soundboard.SystemCmd.configured_executable(:ffmpeg_executable, "ffmpeg") do
      nil ->
        {:error, "ffmpeg is not installed on this host"}

      exe ->
        SessionsPath.ensure_session_dir(session_id)
        playlist = SessionsPath.playlist_path(session_id)
        _ = File.rm(playlist)

        waiter = Keyword.get(opts, :waiter, self())
        notify = Keyword.get(opts, :notify, waiter)
        timeout = Application.get_env(:soundboard, :ffmpeg_live_ready_timeout_ms, 45_000)

        holder =
          spawn(fn ->
            holder_loop(exe, stream_url, playlist, waiter, notify)
          end)

        receive do
          {:live_hls_ready, ^holder, ^playlist} ->
            {:ok, %{playlist_path: playlist, mode: :live, holder_pid: holder}}

          {:live_hls_error, ^holder, reason} ->
            stop(holder)
            {:error, reason}
        after
          timeout ->
            stop(holder)
            {:error, "Timed out waiting for live HLS segments"}
        end
    end
  end

  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      send(pid, :stop)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        2_000 ->
          Process.exit(pid, :kill)
          :ok
      end
    else
      :ok
    end
  end

  defp holder_loop(exe, stream_url, playlist, waiter, notify) do
    args = live_args(stream_url, playlist)

    port =
      Port.open(
        {:spawn_executable, exe},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:args, args},
          {:line, 2048}
        ]
      )

    case wait_for_playlist(playlist, port, 40_000) do
      :ok ->
        send(waiter, {:live_hls_ready, self(), playlist})
        monitor_until_stop(port, notify)

      {:error, reason} ->
        close_port(port)
        send(waiter, {:live_hls_error, self(), reason})
    end
  end

  defp monitor_until_stop(port, notify) do
    receive do
      :stop ->
        close_port(port)

      {^port, {:exit_status, status}} ->
        Logger.info("Live HLS ffmpeg exited with status #{status}")
        if is_pid(notify), do: send(notify, {:live_hls_stopped, self()})

      {^port, {:data, _}} ->
        monitor_until_stop(port, notify)

      _ ->
        monitor_until_stop(port, notify)
    end
  end

  defp wait_for_playlist(playlist, port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_playlist(playlist, port, deadline)
  end

  defp do_wait_for_playlist(playlist, port, deadline) do
    now = System.monotonic_time(:millisecond)

    cond do
      now >= deadline ->
        {:error, "Timed out waiting for live HLS segments"}

      playlist_ready?(playlist) ->
        :ok

      true ->
        receive do
          {^port, {:exit_status, status}} ->
            {:error, "ffmpeg exited before live playlist was ready (status #{status})"}

          {^port, {:data, _}} ->
            do_wait_for_playlist(playlist, port, deadline)
        after
          250 ->
            do_wait_for_playlist(playlist, port, deadline)
        end
    end
  end

  defp playlist_ready?(playlist) do
    case File.read(playlist) do
      {:ok, body} ->
        String.contains?(body, "#EXTINF")

      _ ->
        false
    end
  end

  defp live_args(stream_url, playlist_path) do
    [
      "-hide_banner",
      "-loglevel",
      "warning",
      "-user_agent",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "-reconnect",
      "1",
      "-reconnect_streamed",
      "1",
      "-reconnect_delay_max",
      "5",
      "-i",
      stream_url,
      "-map",
      "0:v:0?",
      "-map",
      "0:a:0?",
      "-c",
      "copy",
      "-f",
      "hls",
      "-hls_time",
      "2",
      # Keep enough segments for smooth browser playback. Discord plays the
      # upstream live URL directly, so list size does not need to match it.
      "-hls_list_size",
      "8",
      "-hls_flags",
      "delete_segments+append_list+omit_endlist",
      "-hls_allow_cache",
      "0",
      playlist_path
    ]
  end

  defp close_port(port) do
    if Port.info(port) do
      Port.close(port)
    end
  rescue
    _ -> :ok
  end
end
