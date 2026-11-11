defmodule SoundboardWeb.Components.Soundboard.TagComponents do
  @moduledoc """
  Shared tag UI helpers for the soundboard modals.
  """
  use Phoenix.Component
  alias SoundboardWeb.Live.Support.LiveTags

  embed_templates "tag_components/*"

  attr :tags, :list, default: []
  attr :remove_event, :string, required: true
  attr :tag_key, :atom, default: :name
  attr :wrapper_class, :string, default: "mt-2 flex flex-wrap gap-2"

  def tag_badge_list(assigns)

  attr :tag_input, :string, default: ""
  attr :tag_suggestions, :list, default: []
  attr :select_event, :string, required: true
  attr :tag_key, :atom, default: :name

  attr :wrapper_class, :string,
    default:
      "absolute z-10 mt-1 w-full bg-white dark:bg-gray-700 shadow-lg max-h-60 rounded-md py-1 text-base overflow-auto focus:outline-none sm:text-sm"

  attr :suggestion_class, :string,
    default:
      "w-full text-left px-4 py-2 text-sm hover:bg-blue-50 dark:hover:bg-blue-900 dark:text-gray-100"

  def tag_suggestions_dropdown(assigns)

  attr :tag, :any, required: true
  attr :selected_tags, :list, required: true
  attr :uploaded_files, :list, required: true
  attr :tag_key, :atom, default: :name
  attr :click_event, :string, default: "toggle_tag_filter"
  attr :class, :any, default: []

  def tag_filter_button(assigns)

  attr :value, :string, default: ""
  attr :placeholder, :string, default: "Type a tag and press Enter..."
  attr :input_id, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :class, :string, default: ""
  attr :onkeydown, :string, default: nil
  attr :autocomplete, :string, default: nil
  attr :rest, :global

  def tag_input_field(assigns)

  defp base_class,
    do:
      "block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm focus:border-blue-500 " <>
        "focus:ring-blue-500 sm:text-sm dark:bg-gray-700 dark:text-gray-100 dark:placeholder-gray-400"

  defp tag_value(tag, tag_key) when is_atom(tag_key) do
    case tag do
      %{^tag_key => value} -> value
      %{} -> Map.get(tag, :name) || tag
      _ -> tag
    end
  end

  defp tag_value(tag, _tag_key), do: tag
end
