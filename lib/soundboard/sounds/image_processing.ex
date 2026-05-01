defmodule Soundboard.Sounds.ImageProcessing do
  @moduledoc """
  Service for processing uploaded images using ffmpeg.
  """

  require Logger

  @target_width 400
  @target_height 300
  @images_dir "priv/static/uploads/images"

  @doc """
  Processes an image file: converts to PNG and resizes/crops to 400x300.
  Returns {:ok, new_filename} or {:error, reason}.
  """
  def process_image(temp_path) do
    new_filename = "#{Ecto.UUID.generate()}.png"
    dest_path = Path.join(@images_dir, new_filename)

    args = [
      "-i",
      temp_path,
      "-vf",
      "scale=#{@target_width}:#{@target_height}:force_original_aspect_ratio=increase,crop=#{@target_width}:#{@target_height}",
      "-y",
      dest_path
    ]

    with :ok <- File.mkdir_p(Path.dirname(dest_path)),
         {_, 0} <- System.cmd("ffmpeg", args, stderr_to_stdout: true) do
      {:ok, new_filename}
    else
      {output, status} ->
        Logger.error("FFmpeg image processing failed with status #{status}: #{output}")
        {:error, "Failed to process image"}

      {:error, reason} ->
        Logger.error("Failed to create images directory: #{inspect(reason)}")
        {:error, "Failed to process image"}
    end
  end

  @doc """
  Deletes an image file if it exists.
  """
  def delete_image(nil), do: :ok
  def delete_image(""), do: :ok

  def delete_image(filename) do
    path = Path.join(@images_dir, filename)

    if File.exists?(path) do
      File.rm(path)
    else
      :ok
    end
  end
end
