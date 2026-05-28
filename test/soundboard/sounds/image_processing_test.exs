defmodule Soundboard.Sounds.ImageProcessingTest do
  use Soundboard.DataCase, async: true
  alias Soundboard.Sounds.ImageProcessing

  @test_image "test/support/fixtures/test_image.png"
  @images_dir "priv/static/uploads/images"

  setup do
    previous_ffmpeg = Application.get_env(:soundboard, :ffmpeg_executable, :system)

    on_exit(fn ->
      case previous_ffmpeg do
        :system -> Application.delete_env(:soundboard, :ffmpeg_executable)
        value -> Application.put_env(:soundboard, :ffmpeg_executable, value)
      end
    end)

    :ok
  end

  @tag :requires_ffmpeg
  test "process_image/1 converts to PNG, downscales large images, preserves small images" do
    assert {:ok, filename} = ImageProcessing.process_image(@test_image)
    assert String.ends_with?(filename, ".png")

    dest_path = Path.join(@images_dir, filename)
    assert File.exists?(dest_path)

    on_exit(fn -> ImageProcessing.delete_image(filename) end)
  end

  test "delete_image/1 handles nil or empty string" do
    assert ImageProcessing.delete_image(nil) == :ok
    assert ImageProcessing.delete_image("") == :ok
  end
end
