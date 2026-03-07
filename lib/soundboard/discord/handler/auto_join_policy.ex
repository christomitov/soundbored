defmodule Soundboard.Discord.Handler.AutoJoinPolicy do
  @moduledoc false

  def mode do
    case Application.get_env(:soundboard, :env) do
      :test -> :enabled
      _ -> if enabled?(), do: :enabled, else: :disabled
    end
  end

  def enabled? do
    case System.get_env("AUTO_JOIN") do
      nil -> false
      value -> truthy_value?(value)
    end
  end

  defp truthy_value?(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in ["true", "1", "yes"]))
  end
end
