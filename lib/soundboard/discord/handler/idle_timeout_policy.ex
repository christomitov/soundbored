defmodule Soundboard.Discord.Handler.IdleTimeoutPolicy do
  @moduledoc false

  require Logger

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
      nil ->
        @default_seconds

      raw ->
        case raw |> String.trim() |> Integer.parse() do
          {n, ""} ->
            n

          _ ->
            Logger.warning("Invalid VOICE_IDLE_TIMEOUT_SECONDS=#{inspect(raw)}; using default")
            @default_seconds
        end
    end
  end
end
