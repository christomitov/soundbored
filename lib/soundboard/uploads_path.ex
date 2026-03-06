defmodule Soundboard.UploadsPath do
  @moduledoc """
  Central source of truth for uploaded sound storage paths.
  """

  @default_relative_dir "priv/static/uploads"

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

  defp expand_dir(path) when is_binary(path) do
    case Path.type(path) do
      :absolute -> path
      _ -> Application.app_dir(:soundboard, path)
    end
  end
end
