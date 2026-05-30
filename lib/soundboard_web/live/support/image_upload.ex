defmodule SoundboardWeb.Live.Support.ImageUpload do
  @moduledoc false

  alias Soundboard.Sounds.ImageProcessing

  @doc """
  Consumes the :image upload entry (if any) and processes it via ffmpeg.
  Returns {:ok, filename}, {:error, reason}, or {:ok, nil} when no entry.
  """
  def process(socket, consume_fn) do
    consume_fn.(socket, :image, fn meta, _entry ->
      {:ok, ImageProcessing.process_image(meta.path)}
    end)
    |> case do
      [{:ok, filename}] -> {:ok, filename}
      [{:error, reason}] -> {:error, reason}
      _ -> {:ok, nil}
    end
  end
end
