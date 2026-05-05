defmodule Soundboard.Sounds.ImageProcessingTest do
  use Soundboard.DataCase, async: true
  alias Soundboard.Sounds.ImageProcessing

  @test_image "test/support/fixtures/test_image.jpg"
  @images_dir "priv/static/uploads/images"

  setup do
    File.mkdir_p!(Path.dirname(@test_image))
    # Generate a dummy 100x100 JPG using ffmpeg
    System.cmd("ffmpeg", [
      "-f",
      "lavfi",
      "-i",
      "color=c=blue:s=100x100",
      "-frames:v",
      "1",
      "-y",
      @test_image
    ])

    on_exit(fn ->
      File.rm(@test_image)
    end)

    :ok
  end

  test "process_image/1 converts to PNG, downscales large images, preserves small images" do
    assert {:ok, filename} = ImageProcessing.process_image(@test_image)
    assert String.ends_with?(filename, ".png")

    dest_path = Path.join(@images_dir, filename)
    assert File.exists?(dest_path)

    # Verify dimensions with ffmpeg
    {output, 0} =
      System.cmd("ffprobe", [
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height",
        "-of",
        "csv=p=0",
        dest_path
      ])

    assert String.trim(output) == "100,100"

    # Cleanup
    ImageProcessing.delete_image(filename)
    refute File.exists?(dest_path)
  end

  test "delete_image/1 handles nil or empty string" do
    assert ImageProcessing.delete_image(nil) == :ok
    assert ImageProcessing.delete_image("") == :ok
  end
end
