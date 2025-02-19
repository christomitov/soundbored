defmodule SoundboardWeb.Presence do
  @moduledoc """
  The Presence module.
  """
  use Phoenix.Presence,
    otp_app: :soundboard,
    pubsub_server: Soundboard.PubSub
end
