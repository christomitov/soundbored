defmodule Soundboard.YouTube.Extractor do
  @moduledoc """
  Downloads YouTube media via yt-dlp for video playback sessions.
  """

  require Logger

  alias Soundboard.SystemCmd
  alias Soundboard.YouTube.{Cookies, YtDlp}

  @url_patterns [
    ~r/^https?:\/\/(?:www\.)?youtube\.com\/watch\?.*\bv=([\w-]{11})/i,
    ~r/^https?:\/\/youtu\.be\/([\w-]{11})/i,
    ~r/^https?:\/\/(?:www\.)?youtube\.com\/shorts\/([\w-]{11})/i,
    ~r/^https?:\/\/(?:www\.)?youtube\.com\/embed\/([\w-]{11})/i
  ]

  # Cap at 720p so Discord remux / HLS stay lighter than 1080p+.
  @format_vod "bv*[height<=720]+ba/b[height<=720]"
  @format_live "b[height<=720]/bv*[height<=720]+ba/b"

  @type extraction :: %{
          title: String.t(),
          thumbnail_url: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          media_path: String.t() | nil,
          stream_url: String.t() | nil,
          live?: boolean(),
          youtube_id: String.t(),
          url: String.t()
        }

  @spec available?() :: boolean()
  def available?, do: not is_nil(executable())

  @spec valid_url?(String.t()) :: boolean()
  def valid_url?(url) when is_binary(url) do
    match?({:ok, _}, youtube_id(url))
  end

  def valid_url?(_), do: false

  @spec youtube_id(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def youtube_id(url) when is_binary(url) do
    url = String.trim(url)

    Enum.find_value(@url_patterns, {:error, "That doesn't look like a valid YouTube URL."}, fn
      pattern ->
        case Regex.run(pattern, url) do
          [_, id] -> {:ok, id}
          _ -> nil
        end
    end)
  end

  @spec thumbnail_url(String.t() | nil) :: String.t() | nil
  def thumbnail_url(youtube_id) when is_binary(youtube_id) and byte_size(youtube_id) > 0 do
    "https://i.ytimg.com/vi/#{youtube_id}/hqdefault.jpg"
  end

  def thumbnail_url(_), do: nil

  @doc """
  Parses a YouTube start timestamp from the URL.

  Supports `t` / `start` query params and `#t=` fragments, including
  `5`, `5s`, `1m30s`, and `1h2m3s`. Returns milliseconds (0 if absent/invalid).
  """
  @spec start_offset_ms(String.t()) :: non_neg_integer()
  def start_offset_ms(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    seconds =
      query_start_seconds(uri.query) ||
        fragment_start_seconds(uri.fragment) ||
        0

    max(seconds, 0) * 1000
  end

  def start_offset_ms(_), do: 0

  @doc """
  Lightweight metadata probe (title, duration, live status) without downloading media.
  """
  @spec probe(String.t()) :: {:ok, map()} | {:error, String.t()}
  def probe(url) when is_binary(url) do
    with :ok <- ensure_available(),
         {:ok, youtube_id} <- youtube_id(url),
         {:ok, meta} <- fetch_metadata(url) do
      {:ok,
       %{
         youtube_id: youtube_id,
         title: meta.title,
         thumbnail_url: meta.thumbnail_url || thumbnail_url(youtube_id),
         duration_ms: meta.duration_seconds && meta.duration_seconds * 1000,
         live_status: meta.live_status,
         live?: meta.live_status == :is_live,
         url: String.trim(url)
       }}
    else
      {:error, reason} = error when is_binary(reason) -> error
      other -> {:error, "Failed to probe YouTube URL: #{inspect(other)}"}
    end
  end

  @spec download(String.t(), String.t()) :: {:ok, extraction()} | {:error, String.t()}
  def download(url, output_dir) when is_binary(url) and is_binary(output_dir) do
    with :ok <- ensure_available(),
         {:ok, youtube_id} <- youtube_id(url),
         :ok <- File.mkdir_p(output_dir),
         {:ok, meta} <- fetch_metadata(url) do
      case meta.live_status do
        :is_upcoming ->
          {:error, "That live stream hasn't started yet."}

        :is_live ->
          resolve_live(url, youtube_id, meta)

        _ ->
          download_vod(url, output_dir, youtube_id, meta)
      end
    else
      {:error, reason} = error when is_binary(reason) -> error
      other -> {:error, "Failed to download YouTube media: #{inspect(other)}"}
    end
  end

  defp resolve_live(url, youtube_id, meta) do
    case resolve_stream_url(url) do
      {:ok, stream_url} ->
        {:ok,
         %{
           title: meta.title,
           thumbnail_url: meta.thumbnail_url || thumbnail_url(youtube_id),
           duration_ms: meta.duration_seconds && meta.duration_seconds * 1000,
           media_path: nil,
           stream_url: stream_url,
           live?: true,
           youtube_id: youtube_id,
           url: url
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp download_vod(url, output_dir, youtube_id, meta) do
    case download_media(url, output_dir, youtube_id) do
      {:ok, media_path} ->
        {:ok,
         %{
           title: meta.title,
           thumbnail_url: meta.thumbnail_url || thumbnail_url(youtube_id),
           duration_ms: meta.duration_seconds * 1000,
           media_path: media_path,
           stream_url: nil,
           live?: false,
           youtube_id: youtube_id,
           url: url
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_start_seconds(nil), do: nil

  defp query_start_seconds(query) do
    params = URI.decode_query(query)
    parse_time_token(params["t"] || params["start"])
  end

  defp fragment_start_seconds(nil), do: nil

  defp fragment_start_seconds(fragment) do
    case Regex.run(~r/^t=(.+)$/i, fragment) do
      [_, token] -> parse_time_token(token)
      _ -> nil
    end
  end

  defp parse_time_token(nil), do: nil
  defp parse_time_token(""), do: nil

  defp parse_time_token(token) when is_binary(token) do
    token = String.trim(token)

    cond do
      Regex.match?(~r/^\d+$/, token) ->
        String.to_integer(token)

      Regex.match?(~r/^\d+\.\d+$/, token) ->
        trunc(String.to_float(token))

      Regex.match?(~r/[hms]/i, token) ->
        parse_hms_token(token)

      true ->
        nil
    end
  end

  defp parse_hms_token(token) do
    down = String.downcase(token)
    capture_unit(down, "h") * 3600 + capture_unit(down, "m") * 60 + capture_unit(down, "s")
  end

  defp capture_unit(token, unit) do
    case Regex.run(~r/(\d+)#{unit}/, token) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp ensure_available do
    if available?(), do: :ok, else: {:error, unavailable_message()}
  end

  defp fetch_metadata(url) do
    args =
      base_args() ++
        [
          "--print",
          "%(title)s",
          "--print",
          "%(duration)s",
          "--print",
          "%(live_status)s",
          "--print",
          "%(thumbnail)s",
          "--skip-download",
          url
        ]

    with {:ok, output} <- run(args) do
      output
      |> String.trim()
      |> String.split("\n", trim: true)
      |> parse_metadata_lines()
    end
  end

  defp parse_metadata_lines([title, duration, live_status, thumbnail | _]) do
    build_metadata(title, duration, live_status, thumbnail)
  end

  defp parse_metadata_lines([title, duration, live_status | _]) do
    build_metadata(title, duration, live_status, nil)
  end

  defp parse_metadata_lines([title, duration | _]) do
    build_metadata(title, duration, "not_live", nil)
  end

  defp parse_metadata_lines(_), do: {:error, "Failed to read video metadata"}

  defp build_metadata(title, duration_string, live_status, thumbnail) do
    duration = parse_duration(duration_string)
    status = normalize_live_status(live_status)

    if is_integer(duration) or status in [:is_live, :is_upcoming] do
      {:ok,
       %{
         title: title,
         duration_seconds: duration,
         live_status: status,
         thumbnail_url: normalize_thumbnail_url(thumbnail)
       }}
    else
      {:error, "Could not determine video duration"}
    end
  end

  defp parse_duration(value) do
    case Integer.parse(value) do
      {duration, _} when duration > 0 -> duration
      _ -> nil
    end
  end

  defp normalize_live_status(status) when is_binary(status) do
    case String.downcase(String.trim(status)) do
      "is_live" -> :is_live
      "is_upcoming" -> :is_upcoming
      "was_live" -> :was_live
      "post_live" -> :was_live
      "true" -> :is_live
      _ -> :not_live
    end
  end

  defp normalize_live_status(_), do: :not_live

  defp normalize_thumbnail_url(url) when is_binary(url) do
    url = String.trim(url)

    if String.starts_with?(url, ["https://", "http://"]), do: url, else: nil
  end

  defp normalize_thumbnail_url(_), do: nil

  defp resolve_stream_url(url) do
    # Prefer a single combined progressive/HLS format for live remux + Discord.
    args = base_args() ++ ["-f", @format_live, "-g", url]

    case run(args) do
      {:ok, output} ->
        stream_url =
          output
          |> String.split("\n", trim: true)
          |> Enum.find(
            &(String.starts_with?(&1, "http://") or String.starts_with?(&1, "https://"))
          )

        if stream_url do
          {:ok, stream_url}
        else
          {:error, "Could not resolve a live stream URL"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp download_media(url, output_dir, youtube_id) do
    out_template = Path.join(output_dir, "#{youtube_id}.%(ext)s")

    args =
      base_args() ++
        [
          "-f",
          @format_vod,
          "--merge-output-format",
          "mp4",
          "-o",
          out_template,
          "--no-progress",
          url
        ]

    case run(args) do
      {:ok, _} ->
        case find_downloaded_file(output_dir, youtube_id) do
          {:ok, path} -> {:ok, path}
          :error -> {:error, "Download finished but media file was not found"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_downloaded_file(output_dir, youtube_id) do
    output_dir
    |> File.ls()
    |> case do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, youtube_id))
        |> Enum.map(&Path.join(output_dir, &1))
        |> Enum.filter(&File.regular?/1)
        |> Enum.reject(&String.ends_with?(&1, [".part", ".ytdl", ".json"]))
        |> List.first()
        |> case do
          nil -> :error
          path -> {:ok, path}
        end

      _ ->
        :error
    end
  end

  defp base_args do
    args = ["--no-playlist", "--no-warnings"] ++ YtDlp.js_runtime_args()

    if Cookies.present?() do
      Logger.debug("Using saved YouTube cookies from #{Cookies.path()}")
      args ++ ["--cookies", Cookies.path()]
    else
      args
    end
  end

  defp run(args) do
    case executable() do
      nil ->
        {:error, unavailable_message()}

      exe ->
        timeout = Application.get_env(:soundboard, :ytdlp_timeout_ms, 120_000)

        case cmd().(exe, args, stderr_to_stdout: true, timeout: timeout) do
          {output, 0} ->
            {:ok, output}

          {output, code} ->
            Logger.warning("yt-dlp failed (#{code}): #{String.slice(output, 0, 500)}")
            {:error, friendly_error(output)}
        end
    end
  end

  defp friendly_error(output) do
    down = String.downcase(output)

    cond do
      String.contains?(down, "sign in") or String.contains?(down, "age") ->
        if Cookies.present?() do
          "YouTube rejected the saved cookies. Re-export them from a logged-in private browser window, close that window immediately, then replace the cookies in Settings."
        else
          "Failed to fetch that video. It may be private, age-restricted, or need cookies."
        end

      String.contains?(down, "private") ->
        "That video is private."

      String.contains?(down, "requested format is not available") or
          String.contains?(down, "only images are available") ->
        if YtDlp.resolve_js_runtime() do
          "Failed to fetch playable formats. Cookies may be incomplete, or YouTube blocked this client."
        else
          "Failed to fetch playable formats. Install Node.js (22+) so yt-dlp can solve YouTube's JS challenge."
        end

      true ->
        "Failed to fetch audio/video from that URL. It may be private, age-restricted, or region-locked."
    end
  end

  defp unavailable_message,
    do: "YouTube playback is not available (yt-dlp not installed)."

  defp executable do
    YtDlp.executable()
  end

  defp cmd do
    Application.get_env(:soundboard, :ytdlp_cmd, &SystemCmd.run/3)
  end
end
