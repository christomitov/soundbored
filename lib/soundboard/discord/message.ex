defmodule Soundboard.Discord.Message do
  @moduledoc false

  alias EDA.API.Message, as: EDAMessage

  def create(channel_id, payload) do
    EDAMessage.create(to_id(channel_id), payload)
  end

  defp to_id(value) when is_integer(value), do: Integer.to_string(value)
  defp to_id(value), do: to_string(value)
end
