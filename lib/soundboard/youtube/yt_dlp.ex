defmodule Soundboard.YouTube.YtDlp do
  @moduledoc """
  Resolves and optionally installs the yt-dlp binary.

  Resolution order:
  1. Explicit `:ytdlp_executable` / `YTDLP_PATH` when the file exists
  2. `yt-dlp` on `PATH`
  3. Managed binary (downloaded on demand if missing)

  On Alpine/musl we download the official Python zipapp (`yt-dlp`) rather than
  the glibc `yt-dlp_linux*` builds, which fail with "not found".
  """

  require Logger

  alias Soundboard.SystemCmd

  @persistent_key {__MODULE__, :executable}
  @release_base "https://github.com/yt-dlp/yt-dlp/releases/latest/download"

  @doc """
  Absolute path used for managed installs.

  When `YTDLP_PATH` / `:ytdlp_executable` is an absolute/relative path string,
  that path is also the download destination. Otherwise uses `:ytdlp_managed_path`.
  """
  @spec managed_path() :: String.t()
  def managed_path do
    case Application.get_env(:soundboard, :ytdlp_executable, :system) do
      path when is_binary(path) and path != "" ->
        expand_path(path)

      _ ->
        managed_path_from_config()
    end
  end

  @doc """
  Returns the resolved yt-dlp executable path, or `nil` if unavailable.
  Does not download; call `ensure/0` at boot to install when missing.
  """
  @spec executable() :: String.t() | nil
  def executable do
    case Application.get_env(:soundboard, :ytdlp_executable, :system) do
      false ->
        nil

      path when is_binary(path) and path != "" ->
        path

      _ ->
        case :persistent_term.get(@persistent_key, :unset) do
          path when is_binary(path) -> path
          false -> nil
          :unset -> find_on_path_or_managed()
        end
    end
  end

  @doc """
  Ensures yt-dlp is available, downloading to the managed path when needed.
  """
  @spec ensure() :: {:ok, String.t()} | {:error, String.t()}
  def ensure do
    case Application.get_env(:soundboard, :ytdlp_executable, :system) do
      false ->
        :persistent_term.put(@persistent_key, false)
        {:error, "yt-dlp is disabled"}

      _ ->
        ensure_existing(resolve_existing())
    end
  end

  defp ensure_existing(nil), do: download_managed()

  defp ensure_existing(path) do
    if runnable?(path) do
      {:ok, remember(path)}
    else
      Logger.warning("yt-dlp at #{path} is not runnable; reinstalling")
      download_managed()
    end
  end

  @spec available?() :: boolean()
  def available?, do: is_binary(executable())

  @doc """
  CLI args so yt-dlp can solve YouTube's JS n-challenge (EJS).

  Without a supported JS runtime, cookies authenticate but only storyboard
  images are returned — age-restricted / signed streams fail with
  "Requested format is not available". Prefer Node on Alpine/musl (Deno's
  official builds are glibc and fail with "not found").
  See https://github.com/yt-dlp/yt-dlp/wiki/EJS
  """
  @spec js_runtime_args() :: [String.t()]
  def js_runtime_args do
    case resolve_js_runtime() do
      {runtime, path} -> ["--js-runtimes", "#{runtime}:#{path}"]
      nil -> []
    end
  end

  @doc """
  Returns `{runtime, path}` for the first usable JS runtime, or `nil`.
  """
  @spec resolve_js_runtime() :: {String.t(), String.t()} | nil
  def resolve_js_runtime do
    candidates =
      for {runtime, names} <- js_runtime_candidates(),
          name <- names,
          path = System.find_executable(name),
          is_binary(path),
          do: {runtime, path}

    List.first(candidates)
  end

  defp js_runtime_candidates do
    [
      # Node is preferred on Alpine — apk nodejs is musl-native.
      {"node", ["node"]},
      {"deno", ["deno"]},
      {"quickjs", ["qjs"]},
      {"bun", ["bun"]}
    ]
  end

  defp resolve_existing do
    case Application.get_env(:soundboard, :ytdlp_executable, :system) do
      false ->
        nil

      path when is_binary(path) and path != "" ->
        path

      _ ->
        find_on_path_or_managed()
    end
  end

  defp find_on_path_or_managed do
    managed = managed_path_from_config()

    cond do
      File.regular?(managed) and runnable?(managed) ->
        managed

      path = System.find_executable("yt-dlp") ->
        if runnable?(path), do: path, else: nil

      true ->
        nil
    end
  end

  defp managed_path_from_config do
    Application.get_env(:soundboard, :ytdlp_managed_path, "priv/bin/yt-dlp")
    |> expand_path()
  end

  defp download_managed do
    if Application.get_env(:soundboard, :ytdlp_auto_download, true) == false do
      {:error, "yt-dlp not found and auto-download is disabled"}
    else
      dest = managed_path()
      File.mkdir_p!(Path.dirname(dest))
      url = download_url()

      Logger.info("Downloading yt-dlp #{url} -> #{dest}")

      case fetch_to_file(url, dest) do
        :ok ->
          _ = File.chmod(dest, 0o755)
          validate_download(dest)

        {:error, reason} ->
          _ = File.rm(dest)
          {:error, "Failed to download yt-dlp: #{reason}"}
      end
    end
  end

  defp validate_download(dest) do
    cond do
      not File.regular?(dest) ->
        {:error, "yt-dlp download finished but binary is missing at #{dest}"}

      not runnable?(dest) ->
        _ = File.rm(dest)

        {:error,
         "Downloaded yt-dlp is not runnable (need python3 on Alpine/musl). Install python3 and retry."}

      true ->
        Logger.info("yt-dlp ready at #{dest}")
        {:ok, remember(dest)}
    end
  end

  # Prefer the Python zipapp on Linux — works on Alpine/musl with python3.
  # Native yt-dlp_linux* builds are glibc-linked and fail with "not found" on Alpine.
  defp download_url do
    case :os.type() do
      {:unix, :darwin} -> "#{@release_base}/yt-dlp_macos"
      {:win32, _} -> "#{@release_base}/yt-dlp.exe"
      _ -> "#{@release_base}/yt-dlp"
    end
  end

  defp runnable?(path) when is_binary(path) do
    case SystemCmd.run(path, ["--version"], stderr_to_stdout: true, timeout: 15_000) do
      {output, 0} when byte_size(output) > 0 -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp fetch_to_file(url, dest) do
    cond do
      curl = System.find_executable("curl") ->
        case SystemCmd.run(
               curl,
               ["-fsSL", "--retry", "3", "-o", dest, url],
               stderr_to_stdout: true,
               timeout: 120_000
             ) do
          {_, 0} -> :ok
          {output, code} -> {:error, "curl exit #{code}: #{String.slice(output, 0, 200)}"}
        end

      wget = System.find_executable("wget") ->
        case SystemCmd.run(
               wget,
               ["-q", "-O", dest, url],
               stderr_to_stdout: true,
               timeout: 120_000
             ) do
          {_, 0} -> :ok
          {output, code} -> {:error, "wget exit #{code}: #{String.slice(output, 0, 200)}"}
        end

      true ->
        httpc_download(url, dest)
    end
  end

  defp httpc_download(url, dest) do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), []}
    http_opts = [timeout: 120_000, connect_timeout: 30_000, autoredirect: true]
    opts = [body_format: :binary, full_result: true]

    case :httpc.request(:get, request, http_opts, opts) do
      {:ok, {{_, 200, _}, _headers, body}} when is_binary(body) ->
        File.write(dest, body)

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp remember(path) when is_binary(path) do
    Application.put_env(:soundboard, :ytdlp_executable, path)
    :persistent_term.put(@persistent_key, path)
    path
  end

  defp expand_path(path) when is_binary(path) do
    case Path.type(path) do
      :absolute -> path
      _ -> Path.expand(path, File.cwd!())
    end
  end
end
