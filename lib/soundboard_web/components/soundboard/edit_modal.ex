defmodule SoundboardWeb.Components.Soundboard.EditModal do
  @moduledoc """
  The edit modal component.
  """
  use Phoenix.Component
  alias Soundboard.Volume
  alias SoundboardWeb.Components.Soundboard.{TagComponents, VolumeControl}

  embed_templates "edit_modal/*"

  attr :flash, :map, default: %{}
  attr :edit_name_error, :string, default: nil
  attr :current_user, :map, required: true
  attr :current_sound, :map, required: true
  attr :tag_input, :string, default: ""
  attr :tag_suggestions, :list, default: []

  def edit_modal(assigns)

  defp loaded_tags(%{tags: tags}) when is_list(tags), do: tags
  defp loaded_tags(_sound), do: []
end
