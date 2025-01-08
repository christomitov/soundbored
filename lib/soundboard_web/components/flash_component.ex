defmodule SoundboardWeb.Components.FlashComponent do
  use Phoenix.Component

  def flash(assigns) do
    ~H"""
    <div class="fixed top-4 right-4 z-50 flex flex-col gap-2">
      <%= if message = Phoenix.Flash.get(@flash, :info) do %>
        <div class="rounded-md bg-blue-50 dark:bg-blue-900 p-4">
          <p class="text-sm font-medium text-blue-800 dark:text-blue-200">
            {message}
          </p>
        </div>
      <% end %>

      <%= if message = Phoenix.Flash.get(@flash, :error) do %>
        <div class="rounded-md bg-red-50 dark:bg-red-900 p-4">
          <p class="text-sm font-medium text-red-800 dark:text-red-200">
            {message}
          </p>
        </div>
      <% end %>
    </div>
    """
  end
end
