defmodule SoundboardWeb.Components.FlashComponent do
  @moduledoc """
  The flash component.
  """
  use Phoenix.Component

  embed_templates "flash_component/*"

  def flash(assigns)
end
