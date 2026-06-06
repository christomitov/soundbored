defmodule Soundboard.FFmpeg do
  @moduledoc """
  Utility module for FFmpeg-related operations, such as checking for the executable.
  This centralizes FFmpeg configuration and allows for easier testing by mocking the executable path.
  """

  @doc """
  Returns the ffmpeg executable path, or nil if unavailable.

  Reads `:ffmpeg_executable` from the `:soundboard` app env:
    - `:system` (default) — resolves via PATH
    - `false` — always nil (useful in tests)
    - binary — used as-is
  """
  def executable do
    case Application.get_env(:soundboard, :ffmpeg_executable, :system) do
      :system -> System.find_executable("ffmpeg")
      false -> nil
      path when is_binary(path) -> path
    end
  end
end
