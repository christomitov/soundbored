defmodule SoundboardWeb.Components.Soundboard.VolumeControl do
  @moduledoc """
  Shared volume slider with preview support for upload/edit modals.
  """
  use Phoenix.Component

  attr :id, :string, default: nil
  attr :value, :integer, required: true
  attr :target, :string, required: true
  attr :push_event, :string, default: "update_volume"
  attr :label, :string, default: "Volume"
  attr :input_name, :string, default: "volume"
  attr :preview_disabled, :boolean, default: false
  attr :preview_label, :string, default: "Preview"
  attr :rest, :global

  def volume_control(assigns) do
    ~H"""
    <div
      id={@id}
      class="mb-4 text-left space-y-2"
      phx-hook="VolumeControl"
      data-push-event={@push_event}
      data-volume-target={@target}
      {@rest}
    >
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300">
        {@label}
      </label>
      <input
        type="range"
        name={@input_name}
        min="0"
        max="100"
        step="1"
        value={@value}
        data-role="volume-slider"
        class="w-full accent-blue-600"
      />
      <div class="flex items-center justify-between text-sm text-gray-600 dark:text-gray-400">
        <span data-role="volume-display">{@value}%</span>
        <button
          type="button"
          data-role="volume-preview"
          class="px-2 py-1 rounded-md border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          disabled={@preview_disabled}
        >
          {@preview_label}
        </button>
      </div>
    </div>
    """
  end
end
