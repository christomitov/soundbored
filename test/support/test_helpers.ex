defmodule Soundboard.TestHelpers do
  @moduledoc """
  Helper functions for testing.
  """

  def audio_fixture_path do
    Path.expand("../fixtures/andthen.mp3", __DIR__)
  end
end
