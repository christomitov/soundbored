defmodule Soundboard.Audio.Duration do
  @moduledoc false

  @spec probe_ms(String.t() | nil) :: pos_integer() | nil
  def probe_ms(path_or_url) when is_binary(path_or_url) and path_or_url != "" do
    case System.find_executable("ffprobe") do
      nil ->
        nil

      ffprobe ->
        {output, 0} =
          System.cmd(
            ffprobe,
            [
              "-v",
              "error",
              "-show_entries",
              "format=duration",
              "-of",
              "default=noprint_wrappers=1:nokey=1",
              path_or_url
            ],
            stderr_to_stdout: true
          )

        parse_ms(output)
    end
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  def probe_ms(_), do: nil

  defp parse_ms(output) do
    case Float.parse(String.trim(output)) do
      {seconds, _} when seconds > 0 -> max(round(seconds * 1000), 1)
      _ -> nil
    end
  end
end
