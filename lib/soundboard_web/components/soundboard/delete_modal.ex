defmodule SoundboardWeb.Components.Soundboard.DeleteModal do
  @moduledoc """
  The delete modal component.
  """
  use Phoenix.Component

  def delete_modal(assigns) do
    ~H"""
    <%= if @show_delete_confirm do %>
      <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity z-50">
        <div class="fixed inset-0 z-50 overflow-y-auto">
          <div class="flex min-h-full items-center justify-center p-4 text-center sm:p-0">
            <div class="relative transform rounded-lg bg-white dark:bg-gray-800 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg">
              <div class="p-6">
                <h3 class="text-lg font-medium text-gray-900 dark:text-gray-100 mb-4">
                  Delete Sound
                </h3>
                <p class="text-gray-600 dark:text-gray-400 mb-4">
                  Are you sure you want to delete this sound? This action cannot be undone.
                </p>
                <div class="flex justify-end gap-3">
                  <button
                    phx-click="hide_delete_confirm"
                    class="inline-flex justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50"
                  >
                    Cancel
                  </button>
                  <button
                    phx-click="delete_sound"
                    class="inline-flex justify-center rounded-md border border-transparent bg-red-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-red-700"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
