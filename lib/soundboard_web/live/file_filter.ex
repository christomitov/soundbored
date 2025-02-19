defmodule SoundboardWeb.Live.FileFilter do
  @moduledoc """
  Filters the files based on the selected tags and search query.
  """

  def filter_files(files, query, selected_tags) do
    files
    |> filter_by_tags(selected_tags)
    |> filter_by_search(query)
  end

  defp filter_by_tags(files, []), do: files

  defp filter_by_tags(files, [tag]) do
    Enum.filter(files, fn file ->
      Enum.any?(file.tags, fn file_tag -> file_tag.id == tag.id end)
    end)
  end

  defp filter_by_search(files, ""), do: files

  defp filter_by_search(files, query) do
    query = String.downcase(query)

    Enum.filter(files, fn file ->
      filename_matches = String.downcase(file.filename) =~ query

      tag_matches =
        Enum.any?(file.tags, fn tag ->
          String.downcase(tag.name) =~ query
        end)

      filename_matches || tag_matches
    end)
  end
end
