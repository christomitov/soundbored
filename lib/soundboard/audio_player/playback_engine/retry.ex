defmodule Soundboard.AudioPlayer.PlaybackEngine.Retry do
  @moduledoc false
  defstruct [:log, :sleep_ms, :stop_first?, :force_refresh?]
end
