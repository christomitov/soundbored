defmodule SoundboardWeb.SoundHelpersTest do
  use ExUnit.Case, async: true

  alias SoundboardWeb.SoundHelpers

  test "display_name handles filenames and non-binaries" do
    assert SoundHelpers.display_name("path/to/test.mp3") == "test"
    assert SoundHelpers.display_name(123) == "123"
    assert SoundHelpers.display_name(nil) == ""
  end

  test "slugify normalizes names and falls back to default" do
    assert SoundHelpers.slugify("My Cool_Sound!") == "my-cool-sound"
    assert SoundHelpers.slugify("   ") == "sound"
  end
end
