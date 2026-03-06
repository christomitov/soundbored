defmodule Soundboard.Sounds.Cache do
  @moduledoc """
  Boundary for invalidating sound playback metadata after sound mutations.
  """

  alias Soundboard.AudioPlayer

  def invalidate(sound_name) when is_binary(sound_name) do
    AudioPlayer.invalidate_cache(sound_name)
  end

  def invalidate(_), do: :ok
end
