defmodule SoundboardWeb.SoundHelpers do
  @moduledoc """
  Shared helpers for formatting sound metadata for UI rendering.
  """

  def display_name(nil), do: ""

  def display_name(filename) when is_binary(filename) do
    filename
    |> Path.basename()
    |> Path.rootname()
  end

  def display_name(other), do: to_string(other)

  def slugify(name) do
    name
    |> display_name()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-", global: true)
    |> String.trim("-")
    |> ensure_slug()
  end

  defp ensure_slug(""), do: "sound"
  defp ensure_slug(slug), do: slug

  # Returns :dark_text, :light_text, or :default (nil/invalid color → no override)
  def text_on_bg(nil), do: :default
  def text_on_bg(""), do: :default

  def text_on_bg("#" <> hex) when byte_size(hex) == 6 do
    r = String.to_integer(String.slice(hex, 0, 2), 16)
    g = String.to_integer(String.slice(hex, 2, 2), 16)
    b = String.to_integer(String.slice(hex, 4, 2), 16)

    if (r * 299 + g * 587 + b * 114) / 1000 >= 128 do
      :dark_text
    else
      :light_text
    end
  end

  def text_on_bg(_), do: :default
end
