defmodule Soundboard.YouTube.Cookies do
  @moduledoc """
  Validates and persists Netscape-format YouTube cookies for yt-dlp.
  """

  require Logger

  alias Soundboard.SystemCmd
  alias Soundboard.YouTube.YtDlp

  @youtube_domain_pattern ~r/(^|\.)youtube\.com$/i
  @meta_filename "cookies.meta.json"
  # A public video does not prove that the exported session is authenticated.
  # Probe a stable age-gated video so "validated" means cookies can unlock the
  # content they are being saved for.
  @validate_url "https://www.youtube.com/watch?v=UqUJkDcwsPA"

  @type status :: %{
          present?: boolean(),
          validated_at: String.t() | nil,
          path: String.t()
        }

  @spec path() :: String.t()
  def path do
    Application.get_env(:soundboard, :youtube_cookies_path, "priv/youtube/cookies.txt")
    |> expand_path()
  end

  @spec status() :: status()
  def status do
    cookies_path = path()
    meta = read_meta()

    %{
      present?: present?(),
      validated_at: Map.get(meta, "validated_at"),
      path: cookies_path
    }
  end

  @spec present?() :: boolean()
  def present? do
    cookies_path = path()
    File.regular?(cookies_path) and readable?(cookies_path)
  end

  defp readable?(cookies_path) do
    case File.open(cookies_path, [:read], fn _io -> :ok end) do
      {:ok, :ok} ->
        true

      {:error, reason} ->
        Logger.warning(
          "YouTube cookies exist but are unreadable at #{cookies_path}: #{inspect(reason)}"
        )

        false
    end
  end

  @spec clear() :: :ok
  def clear do
    cookies_path = path()
    meta_path = meta_path()

    if File.exists?(cookies_path), do: File.rm!(cookies_path)
    if File.exists?(meta_path), do: File.rm!(meta_path)

    :ok
  end

  @spec save(String.t()) :: {:ok, status()} | {:error, String.t()}
  def save(contents) when is_binary(contents) do
    with :ok <- validate_format(contents),
         :ok <- File.mkdir_p(Path.dirname(path())) do
      tmp = tmp_path()

      try do
        with :ok <- File.write(tmp, normalize_contents(contents)),
             :ok <- File.chmod(tmp, 0o600),
             :ok <- validate_with_ytdlp(tmp),
             :ok <- File.cp(tmp, path()),
             :ok <- File.chmod(path(), 0o600),
             :ok <- write_meta(%{"validated_at" => DateTime.utc_now() |> DateTime.to_iso8601()}) do
          {:ok, status()}
        else
          {:error, reason} when is_binary(reason) ->
            {:error, reason}

          {:error, reason} ->
            {:error, "Failed to save cookies: #{inspect(reason)}"}
        end
      after
        _ = File.rm(tmp)
      end
    end
  end

  @spec validate_format(String.t()) :: :ok | {:error, String.t()}
  def validate_format(contents) when is_binary(contents) do
    trimmed = String.trim(contents)

    cond do
      trimmed == "" ->
        {:error, "Cookies content is empty"}

      looks_like_html?(trimmed) ->
        {:error, "Cookies content looks like HTML, not a Netscape cookies.txt file"}

      true ->
        youtube_rows =
          trimmed
          |> String.split(~r/\r?\n/, trim: true)
          |> Enum.filter(&(cookie_row?(&1) and youtube_cookie_row?(&1)))

        if youtube_rows == [] do
          {:error, "No valid .youtube.com cookie rows found"}
        else
          :ok
        end
    end
  end

  defp validate_with_ytdlp(cookies_path) do
    if Application.get_env(:soundboard, :youtube_cookies_skip_ytdlp_validate, false) do
      :ok
    else
      validate_with_executable(cookies_path, ytdlp_executable())
    end
  end

  defp validate_with_executable(_cookies_path, nil) do
    {:error, "yt-dlp is not installed; cannot validate cookies"}
  end

  defp validate_with_executable(cookies_path, executable) do
    # Use -F: success means cookies authenticated. YouTube may still omit
    # playable formats (PO token / SABR); that is not a cookie-file failure.
    args =
      ["--cookies", cookies_path, "-F", "--no-playlist", "--no-warnings"] ++
        YtDlp.js_runtime_args() ++ [@validate_url]

    timeout = Application.get_env(:soundboard, :ytdlp_timeout_ms, 60_000)

    cmd().(executable, args, stderr_to_stdout: true, timeout: timeout)
    |> validate_command_result()
  end

  defp validate_command_result({_output, 0}), do: :ok

  defp validate_command_result({output, code}) do
    trimmed = output |> to_string() |> String.trim()
    Logger.warning("yt-dlp cookie validation failed (#{code}): #{trimmed}")
    validation_failure(String.downcase(trimmed), trimmed, code)
  end

  defp validation_failure(down, trimmed, code) do
    cond do
      cookies_rejected?(down) ->
        {:error,
         "YouTube rejected these cookies (expired, logged out, or incomplete export). Re-export from a logged-in browser session."}

      formats_unavailable?(down) ->
        :ok

      true ->
        empty_validation_failure(trimmed, code)
    end
  end

  defp empty_validation_failure("", code) when code in [126, 127] do
    {:error, "yt-dlp binary is not runnable on this host (reinstall yt-dlp / install python3)"}
  end

  defp empty_validation_failure("", code), do: {:error, "yt-dlp exited #{code} with no output"}

  defp empty_validation_failure(trimmed, _code) do
    {:error, "Cookie validation failed: #{String.slice(trimmed, 0, 300)}"}
  end

  defp cookies_rejected?(down) do
    String.contains?(down, "sign in to confirm") or
      String.contains?(down, "age-restricted") or
      String.contains?(down, "cookies are no longer valid") or
      String.contains?(down, "http error 401") or
      String.contains?(down, "http error 403")
  end

  defp formats_unavailable?(down) do
    String.contains?(down, "no video formats") or
      String.contains?(down, "requested format is not available")
  end

  defp cookie_row?(line) do
    line = String.trim(line)

    cond do
      line == "" -> false
      String.starts_with?(line, "#HttpOnly_") -> true
      String.starts_with?(line, "#") -> false
      true -> true
    end
  end

  defp youtube_cookie_row?(line) do
    line =
      line
      |> String.trim()
      |> String.replace_prefix("#HttpOnly_", "")

    parts = String.split(line, "\t")

    with true <- length(parts) >= 7,
         domain <- Enum.at(parts, 0) |> String.trim() |> String.trim_leading(".") do
      Regex.match?(@youtube_domain_pattern, domain) or
        String.contains?(String.downcase(domain), "youtube.com")
    else
      _ -> false
    end
  end

  defp looks_like_html?(contents) do
    downcased = String.downcase(contents)
    String.contains?(downcased, "<html") or String.contains?(downcased, "<!doctype")
  end

  defp normalize_contents(contents) do
    contents
    |> String.replace("\r\n", "\n")
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp write_meta(map) do
    meta_path = meta_path()
    File.mkdir_p!(Path.dirname(meta_path))
    File.write(meta_path, Jason.encode!(map))
  end

  defp read_meta do
    case File.read(meta_path()) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp meta_path, do: Path.join(Path.dirname(path()), @meta_filename)

  defp tmp_path do
    Path.join(Path.dirname(path()), "cookies.tmp.#{System.unique_integer([:positive])}")
  end

  defp expand_path(path) when is_binary(path) do
    case Path.type(path) do
      :absolute -> path
      _ -> Application.app_dir(:soundboard, path)
    end
  end

  defp ytdlp_executable do
    YtDlp.executable()
  end

  defp cmd do
    Application.get_env(:soundboard, :ytdlp_cmd, &SystemCmd.run/3)
  end
end
