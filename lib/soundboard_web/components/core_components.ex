defmodule SoundboardWeb.CoreComponents do
  @moduledoc """
  The flash notices and icons every page uses, and the JS commands that show
  and hide them. Icons are [heroicons](https://heroicons.com), bundled into
  app.css by the Tailwind plugin.
  """
  use Phoenix.Component
  use Gettext, backend: SoundboardWeb.Gettext

  alias Phoenix.LiveView.JS

  embed_templates "core_components/*"

  @doc """
  Renders a flash notice: the inner block if given, otherwise the flash
  message of the given kind.

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, default: nil, doc: "the container's id; `flash-<kind>` when not given"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns)

  @doc """
  The info and error flashes, and the notices shown while the connection is
  lost.

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns)

  @doc """
  Renders a heroicon by its class name, sized and coloured with classes.

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns), do: ~H"<span class={[@name, @class]} />"

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  defp flash_id(nil, kind), do: "flash-#{kind}"
  defp flash_id(id, _kind), do: id
end
