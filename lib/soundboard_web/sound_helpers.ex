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
end
