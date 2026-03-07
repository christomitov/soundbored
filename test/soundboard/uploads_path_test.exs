defmodule Soundboard.UploadsPathTest do
  use ExUnit.Case, async: false

  alias Soundboard.UploadsPath

  setup do
    original_uploads_dir = Application.get_env(:soundboard, :uploads_dir)

    on_exit(fn ->
      if is_nil(original_uploads_dir) do
        Application.delete_env(:soundboard, :uploads_dir)
      else
        Application.put_env(:soundboard, :uploads_dir, original_uploads_dir)
      end
    end)

    :ok
  end

  test "dir/0 expands relative configured paths inside the application dir" do
    Application.put_env(:soundboard, :uploads_dir, "tmp/test_uploads")

    assert UploadsPath.dir() == Application.app_dir(:soundboard, "tmp/test_uploads")
  end

  test "dir/0 preserves absolute configured paths" do
    absolute = Path.join(System.tmp_dir!(), "soundboard-uploads")
    Application.put_env(:soundboard, :uploads_dir, absolute)

    assert UploadsPath.dir() == absolute
  end

  test "file_path/1 and joined_path/1 build paths relative to uploads dir" do
    base = Path.join(System.tmp_dir!(), "soundboard-uploads-paths")
    Application.put_env(:soundboard, :uploads_dir, base)

    assert UploadsPath.file_path("beep.mp3") == Path.join(base, "beep.mp3")
    assert UploadsPath.joined_path("nested/beep.mp3") == Path.join(base, "nested/beep.mp3")

    assert UploadsPath.joined_path(["nested", "beep.mp3"]) ==
             Path.join([base, "nested", "beep.mp3"])
  end

  test "safe_joined_path/1 allows in-directory paths and rejects traversal" do
    base = Path.join(System.tmp_dir!(), "soundboard-safe-uploads")
    Application.put_env(:soundboard, :uploads_dir, base)

    assert {:ok, ^base} = UploadsPath.safe_joined_path(["."])

    assert {:ok, safe_path} = UploadsPath.safe_joined_path(["nested", "clip.mp3"])
    assert safe_path == Path.join([base, "nested", "clip.mp3"]) |> Path.expand()

    assert :error = UploadsPath.safe_joined_path(["..", "escape.mp3"])
    assert :error = UploadsPath.safe_joined_path("../escape.mp3")
  end
end
