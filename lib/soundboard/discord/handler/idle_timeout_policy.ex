defmodule Soundboard.Discord.Handler.IdleTimeoutPolicy do
  @moduledoc false

  @default_minutes 10

  def timeout_ms do
    minutes =
      case System.get_env("VOICE_IDLE_TIMEOUT_MINUTES") do
        nil -> @default_minutes
        raw -> raw |> String.trim() |> String.to_integer()
      end

    minutes * 60_000
  end
end
