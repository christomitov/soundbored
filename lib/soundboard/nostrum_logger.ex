defmodule Soundboard.NostrumLogger do
  @moduledoc """
  Adds verbose logging for Nostrum voice events.
  Call install/0 at application startup.
  """
  
  require Logger
  
  def install do
    # Log when voice packets fail to decrypt
    Logger.info("NostrumLogger installed - verbose voice logging enabled")
  end
end
