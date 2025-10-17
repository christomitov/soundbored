defmodule Soundboard.Volume do
  @moduledoc """
  Helpers for working with volume percentages and decimal ratios.
  """

  @type percent :: 0..100

  @spec clamp_percent(number()) :: percent()
  def clamp_percent(value) do
    value
    |> round()
    |> min(100)
    |> max(0)
  end

  @spec normalize_percent(String.t() | number() | nil, percent()) :: percent()
  def normalize_percent(value, default_percent) do
    default_percent
    |> clamp_percent()
    |> do_normalize(value)
  end

  @spec percent_to_decimal(String.t() | number() | nil) :: float()
  def percent_to_decimal(percent), do: percent_to_decimal(percent, 100)

  @spec percent_to_decimal(String.t() | number() | nil, percent()) :: float()
  def percent_to_decimal(value, default_percent) do
    value
    |> normalize_percent(default_percent)
    |> convert_percent_to_decimal()
  end

  @spec decimal_to_percent(float() | nil) :: percent()
  def decimal_to_percent(nil), do: 100

  def decimal_to_percent(decimal) when is_number(decimal) do
    decimal
    |> Kernel.*(100)
    |> clamp_percent()
  end

  defp do_normalize(default, nil), do: default
  defp do_normalize(_default, value) when is_integer(value), do: clamp_percent(value)
  defp do_normalize(_default, value) when is_float(value), do: clamp_percent(value)

  defp do_normalize(default, value) when is_binary(value) do
    value
    |> String.trim()
    |> Float.parse()
    |> case do
      {parsed, _rest} -> clamp_percent(parsed)
      :error -> default
    end
  end

  defp do_normalize(default, _), do: default

  defp convert_percent_to_decimal(percent) when percent in 0..100 do
    Float.round(percent / 100, 4)
  end
end
