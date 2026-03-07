defmodule Soundboard.UploadsPath do
  @moduledoc """
  Central source of truth for uploaded sound storage paths.
  """

  @default_relative_dir "priv/static/uploads"

  @type path_input :: String.t() | [String.t()]

  def dir do
    Application.get_env(:soundboard, :uploads_dir, @default_relative_dir)
    |> expand_dir()
  end

  def file_path(filename) when is_binary(filename) do
    Path.join(dir(), filename)
  end

  def joined_path(path_segments) when is_list(path_segments) do
    Path.join([dir() | path_segments])
  end

  def joined_path(path) when is_binary(path) do
    Path.join(dir(), path)
  end

  @spec safe_joined_path(path_input()) :: {:ok, String.t()} | :error
  def safe_joined_path(path) do
    base_dir = dir() |> Path.expand()

    candidate =
      path
      |> normalize_path_segments()
      |> then(&Path.join([base_dir | &1]))
      |> Path.expand()

    if within_uploads_dir?(candidate, base_dir) do
      {:ok, candidate}
    else
      :error
    end
  end

  defp normalize_path_segments(path) when is_binary(path), do: [path]
  defp normalize_path_segments(path_segments) when is_list(path_segments), do: path_segments

  defp within_uploads_dir?(candidate, base_dir) do
    candidate == base_dir or String.starts_with?(candidate, base_dir <> "/")
  end

  defp expand_dir(path) when is_binary(path) do
    case Path.type(path) do
      :absolute -> path
      _ -> Application.app_dir(:soundboard, path)
    end
  end
end
