defmodule SoundboardWeb.Components.Soundboard.SoundCard do
  @moduledoc false
  use Phoenix.Component

  attr :image_filename, :string, default: nil
  attr :contrast, :atom, default: :default
  attr :class, :string, default: ""
  attr :icon_class, :string, default: "w-8 h-8"

  def sound_image(assigns) do
    ~H"""
    <div class={@class}>
      <%= if @image_filename do %>
        <img src={"/uploads/images/#{@image_filename}"} class="max-w-full max-h-full" />
      <% else %>
        <div class={["w-full h-full flex items-center justify-center", contrast_bg(@contrast)]}>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="currentColor"
            class={[@icon_class, contrast_icon(@contrast)]}
          >
            <path d="M13.5 4.06c0-1.336-1.616-2.005-2.56-1.06l-4.5 4.5H4.508c-1.141 0-2.318.664-2.66 1.905A9.76 9.76 0 0 0 1.5 12c0 .898.121 1.768.35 2.595.341 1.24 1.518 1.905 2.659 1.905H6.44l4.5 4.5c.945.945 2.561.276 2.561-1.06V4.06ZM18.584 5.106a.75.75 0 0 1 1.06 0c3.808 3.807 3.808 9.98 0 13.788a.75.75 0 0 1-1.06-1.06 8.25 8.25 0 0 0 0-11.668.75.75 0 0 1 0-1.06Z" />
            <path d="M15.932 7.757a.75.75 0 0 1 1.061 0 6 6 0 0 1 0 8.486.75.75 0 0 1-1.06-1.061 4.5 4.5 0 0 0 0-6.364.75.75 0 0 1 0-1.06Z" />
          </svg>
        </div>
      <% end %>
    </div>
    """
  end

  defp contrast_bg(:dark_text), do: "bg-black/5"
  defp contrast_bg(:light_text), do: "bg-white/10"
  defp contrast_bg(:default), do: "bg-gray-100 dark:bg-gray-700"

  defp contrast_icon(:dark_text), do: "text-black/20"
  defp contrast_icon(:light_text), do: "text-white/30"
  defp contrast_icon(:default), do: "text-gray-300 dark:text-gray-600"
end
