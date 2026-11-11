defmodule Soundboard.Discord.Handler.AutoJoinPolicy do
  @moduledoc false

  @type mode :: :presence | :play | false

  @spec mode() :: mode()
  def mode, do: parse_mode(System.get_env("AUTO_JOIN"))

  defp parse_mode(nil), do: :play

  defp parse_mode(value) do
    case value |> String.trim() |> String.downcase() do
      v when v in ["presence", "true", "1", "yes"] -> :presence
      "play" -> :play
      _ -> false
    end
  end
end
