defmodule SoundboardWeb.Live.LiveTags do
  @moduledoc """
  LiveView-facing tag queries and mutations for the soundboard.
  """

  alias Soundboard.{PubSubTopics, Sounds.Tags}

  def add_tag(tag_name, current_tags, apply_tag_fun) when is_function(apply_tag_fun, 2) do
    with {:ok} <- validate_tag_name(tag_name),
         {:ok, tag} <- Tags.find_or_create(tag_name),
         {:ok} <- validate_unique_tag(tag, current_tags) do
      apply_tag_fun.(tag, current_tags)
    end
  end

  def search(query), do: Tags.search(query)
  def all_tags(sounds), do: Tags.all_for_sounds(sounds)
  def count_sounds_with_tag(sounds, tag), do: Tags.count_sounds_with_tag(sounds, tag)
  def tag_selected?(tag, selected_tags), do: Tags.tag_selected?(tag, selected_tags)
  def update_sound_tags(sound, tags), do: Tags.update_sound_tags(sound, tags)
  def find_or_create_tag(name), do: Tags.find_or_create(name)
  def list_tags_for_sound(filename), do: Tags.list_for_sound(filename)

  def broadcast_update do
    PubSubTopics.broadcast_files_updated()
  end

  defp validate_tag_name(tag_name) do
    if String.trim(to_string(tag_name)) == "" do
      {:error, "Tag name cannot be empty"}
    else
      {:ok}
    end
  end

  defp validate_unique_tag(tag, current_tags) do
    if Enum.any?(current_tags, &(&1.id == tag.id)) do
      {:error, "Tag already exists"}
    else
      {:ok}
    end
  end
end
