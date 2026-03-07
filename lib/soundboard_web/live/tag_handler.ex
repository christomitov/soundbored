defmodule SoundboardWeb.Live.TagHandler do
  @moduledoc """
  Handles UI-oriented tag interactions for sounds and uploads.
  """

  alias Phoenix.PubSub
  alias Soundboard.Sounds.Tags
  import Phoenix.Component, only: [assign: 3]

  def add_tag(socket, tag_name, current_tags) do
    with {:ok} <- validate_tag_name(tag_name),
         {:ok, tag} <- Tags.find_or_create(tag_name),
         {:ok} <- validate_unique_tag(tag, current_tags) do
      add_tag_to_sound_or_upload(socket, tag, current_tags)
    end
  end

  def remove_tag(socket, tag_name) do
    sound = socket.assigns.current_sound
    tags = Enum.reject(sound.tags, &(&1.name == tag_name))

    case Tags.update_sound_tags(sound, tags) do
      {:ok, updated_sound} ->
        broadcast_update()
        {:ok, updated_sound}

      {:error, _} ->
        {:error, "Failed to remove tag"}
    end
  end

  def search_tags(query), do: Tags.search(query)
  def all_tags(sounds), do: Tags.all_for_sounds(sounds)
  def count_sounds_with_tag(sounds, tag), do: Tags.count_sounds_with_tag(sounds, tag)
  def tag_selected?(tag, selected_tags), do: Tags.tag_selected?(tag, selected_tags)
  def update_sound_tags(sound, tags), do: Tags.update_sound_tags(sound, tags)
  def find_or_create_tag(name), do: Tags.find_or_create(name)
  def list_tags_for_sound(filename), do: Tags.list_for_sound(filename)

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

  defp add_tag_to_sound_or_upload(socket, tag, current_tags) do
    if socket.assigns.current_sound do
      add_tag_to_sound(socket, tag, current_tags)
    else
      {:ok, assign(socket, :upload_tags, [tag | current_tags])}
    end
  end

  defp add_tag_to_sound(socket, tag, current_tags) do
    case Tags.update_sound_tags(socket.assigns.current_sound, [tag | current_tags]) do
      {:ok, updated_sound} ->
        broadcast_update()
        {:ok, assign(socket, :current_sound, updated_sound)}

      {:error, _} ->
        {:error, "Failed to add tag"}
    end
  end

  defp broadcast_update do
    PubSub.broadcast(Soundboard.PubSub, "soundboard", {:files_updated})
  end
end
