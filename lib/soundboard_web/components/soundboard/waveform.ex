defmodule SoundboardWeb.Components.Soundboard.Waveform do
  @moduledoc """
  Deterministic decorative waveform SVG bars for desk-theme pads.
  """
  use Phoenix.Component

  attr :seed, :integer, required: true
  attr :bars, :integer, default: 34
  attr :class, :string, default: "wave"
  attr :bar_class, :string, default: "bar"

  def waveform(assigns) do
    ~H"""
    <svg class={@class} viewBox="0 0 100 40" preserveAspectRatio="none" aria-hidden="true">
      <%= for {height, index} <- Enum.with_index(heights(@seed, @bars)) do %>
        <% width = 100 / @bars %>
        <rect
          class={@bar_class}
          x={"#{Float.round(index * width, 2)}%"}
          y={"#{Float.round((1 - height) * 50, 2)}%"}
          width={"#{Float.round(width * 0.62, 2)}%"}
          height={"#{Float.round(height * 100, 2)}%"}
          rx="0.6"
        />
      <% end %>
    </svg>
    """
  end

  defp heights(seed, n) do
    # Cascading LCG so each seed produces a distinct bar sequence (matches desk mockup).
    {heights, _} =
      Enum.map_reduce(0..(n - 1), rem(seed * 9301 + 49_297, 233_280), fn i, x ->
        x = rem(x * 9301 + 49_297, 233_280)
        env = :math.pow(:math.sin(:math.pi() * i / max(n, 1)), 0.55)
        height = 0.16 + x / 233_280 * 0.84 * env
        {height, x}
      end)

    heights
  end
end
