defmodule SoundboardWeb.Components.Soundboard.ColorPicker do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :checked, :boolean, default: false
  attr :color, :string, default: "#ffffff"
  attr :disabled, :boolean, default: false

  def color_picker(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left">
        Card Color
      </label>
      <div class="mt-1 flex items-center gap-3">
        <input
          type="checkbox"
          id={@id}
          class={[
            "peer h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600 cursor-pointer",
            @disabled && "disabled:opacity-50 disabled:cursor-not-allowed"
          ]}
          name="use_custom_color"
          value="true"
          checked={@checked}
          disabled={@disabled}
        />
        <label
          for={@id}
          class="text-sm text-gray-500 dark:text-gray-400 cursor-pointer select-none"
        >
          Custom
        </label>
        <input
          type="color"
          name="color"
          value={@color}
          disabled={@disabled}
          class={[
            "h-8 w-12 rounded cursor-pointer transition-opacity",
            "opacity-30 pointer-events-none",
            "peer-checked:opacity-100 peer-checked:pointer-events-auto",
            @disabled && "disabled:opacity-30"
          ]}
        />
      </div>
    </div>
    """
  end
end
