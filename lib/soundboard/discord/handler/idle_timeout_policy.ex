defmodule Soundboard.Discord.Handler.IdleTimeoutPolicy do
  @moduledoc false

  @default_seconds 600

  @spec timeout_ms() :: pos_integer() | nil
  def timeout_ms do
    case raw_seconds() do
      n when n <= 0 -> nil
      n -> n * 1_000
    end
  end

  defp raw_seconds do
    case System.get_env("VOICE_IDLE_TIMEOUT_SECONDS") do
      nil -> @default_seconds
      raw -> raw |> String.trim() |> String.to_integer()
    end
  end
end
