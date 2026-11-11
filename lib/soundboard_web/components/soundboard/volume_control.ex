defmodule SoundboardWeb.Components.Soundboard.VolumeControl do
  @moduledoc """
  Shared volume slider with preview support for upload/edit modals.
  """
  use Phoenix.Component

  embed_templates "volume_control/*"

  attr :id, :string, default: nil
  attr :value, :integer, required: true
  attr :target, :string, required: true
  attr :push_event, :string, default: "update_volume"
  attr :label, :string, default: "Volume"
  attr :input_name, :string, default: "volume"
  attr :preview_disabled, :boolean, default: false
  attr :preview_label, :string, default: "Preview"
  attr :max_percent, :integer, default: 150
  attr :rest, :global

  def volume_control(assigns)
end
