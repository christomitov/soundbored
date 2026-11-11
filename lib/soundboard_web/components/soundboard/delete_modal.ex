defmodule SoundboardWeb.Components.Soundboard.DeleteModal do
  @moduledoc """
  The delete modal component.
  """
  use Phoenix.Component

  embed_templates "delete_modal/*"

  def delete_modal(assigns)
end
