defmodule Soundboard.Sounds.Tags do
  @moduledoc """
  Domain helpers for searching, resolving, and persisting sound tags.
  """

  import Ecto.Changeset

  alias Soundboard.{Repo, Sound, Tag}

  def search(query) do
    Tag.search(query)
    |> Repo.all()
  end

  def all_for_sounds(sounds) do
    sounds
    |> Enum.flat_map(& &1.tags)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  def count_sounds_with_tag(sounds, tag) do
    Enum.count(sounds, fn sound ->
      Enum.any?(sound.tags, &(&1.id == tag.id))
    end)
  end

  def tag_selected?(tag, selected_tags) do
    Enum.any?(selected_tags, &(&1.id == tag.id))
  end

  def update_sound_tags(sound, tags) do
    sound
    |> Repo.preload(:tags)
    |> Sound.changeset(%{tags: tags})
    |> Repo.update()
  end

  def resolve_many(tags) when is_list(tags) do
    tags
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn tag, {:ok, acc} ->
      case resolve(tag) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, resolved_tag} -> {:cont, {:ok, [resolved_tag | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tag_list} -> {:ok, Enum.reverse(tag_list) |> Enum.uniq_by(& &1.id)}
      error -> error
    end
  end

  def resolve_many(_), do: {:ok, []}

  def resolve(%Tag{} = tag), do: {:ok, tag}

  def resolve(tag_name) when is_binary(tag_name) do
    normalized =
      tag_name
      |> String.trim()
      |> String.downcase()

    if normalized == "" do
      {:error, add_error(change(%Sound{}), :tags, "can't be blank")}
    else
      find_or_create(normalized)
    end
  end

  def resolve(_), do: {:ok, nil}

  def find_or_create(name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()

    case Repo.get_by(Tag, name: normalized) do
      %Tag{} = tag -> {:ok, tag}
      nil -> insert_or_get(normalized)
    end
  end

  def list_for_sound(filename) do
    case Repo.get_by(Sound, filename: filename) do
      nil -> []
      sound -> sound |> Repo.preload(:tags) |> Map.get(:tags)
    end
  end

  defp insert_or_get(name) do
    case %Tag{} |> Tag.changeset(%{name: name}) |> Repo.insert() do
      {:ok, tag} -> {:ok, tag}
      {:error, _} -> fetch_after_insert_conflict(name)
    end
  end

  defp fetch_after_insert_conflict(name) do
    case Repo.get_by(Tag, name: name) do
      %Tag{} = tag -> {:ok, tag}
      nil -> {:error, add_error(change(%Sound{}), :tags, "is invalid")}
    end
  end
end
