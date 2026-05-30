defmodule SoundboardWeb.Components.Soundboard.ImagePicker do
  @moduledoc false
  use Phoenix.Component

  attr :upload, :map, required: true
  attr :current_image_filename, :string, default: nil
  attr :clear_image, :boolean, default: false

  def image_picker(assigns) do
    ~H"""
    <div>
      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 text-left">
        Image
      </label>
      <%= if entry = List.first(@upload.entries) do %>
        <div class="mt-1 mb-2 relative rounded overflow-hidden h-32 flex items-center justify-center bg-gray-100 dark:bg-gray-700">
          <.live_img_preview entry={entry} class="max-w-full max-h-full" />
        </div>
      <% else %>
        <%= if @current_image_filename && !@clear_image do %>
          <div class="mt-1 mb-2 relative rounded overflow-hidden h-32 flex items-center justify-center">
            <img
              src={"/uploads/images/#{@current_image_filename}"}
              class="max-w-full max-h-full"
            />
            <button
              type="button"
              phx-click="remove_image"
              class="absolute top-1 right-1 flex items-center justify-center w-6 h-6
                     rounded-full bg-black/50 hover:bg-black/70 text-white text-sm leading-none"
            >
              &times;
            </button>
          </div>
        <% end %>
      <% end %>
      <.live_file_input
        upload={@upload}
        class="mt-1 block w-full text-sm text-gray-500 dark:text-gray-400
               file:mr-4 file:py-2 file:px-4
               file:rounded-md file:border-0
               file:text-sm file:font-semibold
               file:bg-blue-50 file:text-blue-700
               dark:file:bg-blue-900 dark:file:text-blue-300
               hover:file:bg-blue-100 dark:hover:file:bg-blue-800"
      />
    </div>
    """
  end
end
