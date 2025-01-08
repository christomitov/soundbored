defmodule SoundboardWeb.Presence do
  use Phoenix.Presence,
    otp_app: :soundboard,
    pubsub_server: Soundboard.PubSub
end
