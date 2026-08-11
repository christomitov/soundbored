defmodule Soundboard.Theme do
  @moduledoc """
  Available UI themes and helpers for normalizing theme preferences.
  """

  @themes %{
    "classic" => %{
      id: "classic",
      label: "Classic",
      description: "The original dark soundboard layout."
    },
    "desk" => %{
      id: "desk",
      label: "Desk MK II",
      description: "Hardware faceplate pads on a studio desk."
    },
    "retro" => %{
      id: "retro",
      label: "Retro Riso",
      description: "Cobalt, hot pink, and off-register ink on warm paper stock."
    }
  }

  @default "desk"

  @type t :: String.t()

  @spec default() :: t()
  def default, do: @default

  @spec all() :: [map()]
  def all, do: Map.values(@themes)

  @spec valid?(term()) :: boolean()
  def valid?(theme) when is_binary(theme), do: Map.has_key?(@themes, theme)
  def valid?(_), do: false

  @spec normalize(term()) :: t()
  def normalize(theme) when is_binary(theme) do
    if valid?(theme), do: theme, else: @default
  end

  def normalize(_), do: @default

  @spec get(t()) :: map()
  def get(theme) do
    Map.fetch!(@themes, normalize(theme))
  end

  @spec desk?(term()) :: boolean()
  def desk?(theme), do: normalize(theme) == "desk"

  @spec classic?(term()) :: boolean()
  def classic?(theme), do: normalize(theme) == "classic"

  @spec retro?(term()) :: boolean()
  def retro?(theme), do: normalize(theme) == "retro"
end
