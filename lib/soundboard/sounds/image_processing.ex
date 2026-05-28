defmodule Soundboard.Sounds.ImageProcessing do
  @moduledoc """
  Service for processing uploaded images using ffmpeg.
  """

  alias Soundboard.UploadsPath

  require Logger

  @target_width 400
  @target_height 300

  @doc """
  Processes an image file: converts to PNG and scales to fit within 400x300 (preserving aspect ratio, no upscaling).
  Returns {:ok, new_filename} or {:error, reason}.
  """
  def process_image(temp_path) do
    new_filename = "#{Ecto.UUID.generate()}.png"
    dest_path = Path.join(images_dir(), new_filename)

    args = [
      "-i",
      temp_path,
      "-vf",
      "scale='min(iw,#{@target_width})':'min(ih,#{@target_height})':force_original_aspect_ratio=decrease",
      "-y",
      dest_path
    ]

    case Soundboard.FFmpeg.executable() do
      nil ->
        Logger.error("ffmpeg not found in PATH. Cannot process image.")
        {:error, "ffmpeg not available"}

      ffmpeg ->
        with :ok <- File.mkdir_p(Path.dirname(dest_path)),
             {_, 0} <- System.cmd(ffmpeg, args, stderr_to_stdout: true) do
          {:ok, new_filename}
        else
          {:error, reason} ->
            Logger.error("Failed to create images directory: #{inspect(reason)}")
            {:error, "Failed to process image"}

          {output, status} ->
            Logger.error("FFmpeg image processing failed with status #{status}: #{output}")
            {:error, "Failed to process image"}
        end
    end
  end

  @doc """
  Deletes an image file if it exists.
  """
  def delete_image(nil), do: :ok
  def delete_image(""), do: :ok

  def delete_image(filename) do
    path = Path.join(images_dir(), filename)

    if File.exists?(path) do
      File.rm(path)
    else
      :ok
    end
  end

  defp images_dir, do: UploadsPath.joined_path("images")
end
