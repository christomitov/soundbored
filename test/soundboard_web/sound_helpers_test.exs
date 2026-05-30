defmodule SoundboardWeb.SoundHelpersTest do
  use ExUnit.Case, async: true
  alias SoundboardWeb.SoundHelpers

  describe "display_name/1" do
    test "strips extension and directories" do
      assert SoundHelpers.display_name("priv/static/uploads/beep.mp3") == "beep"
    end

    test "handles values without extension" do
      assert SoundHelpers.display_name("wow") == "wow"
    end

    test "handles nil" do
      assert SoundHelpers.display_name(nil) == ""
    end

    test "stringifies non-binary values" do
      assert SoundHelpers.display_name(123) == "123"
    end
  end

  describe "slugify/1" do
    test "converts filename to lower-case slug" do
      assert SoundHelpers.slugify("Wow Sound.MP3") == "wow-sound"
    end

    test "falls back to default" do
      assert SoundHelpers.slugify(nil) == "sound"
    end
  end

  describe "text_on_bg/1" do
    test "returns :default for nil" do
      assert SoundHelpers.text_on_bg(nil) == :default
    end

    test "returns :default for empty string" do
      assert SoundHelpers.text_on_bg("") == :default
    end

    test "returns :default for non-hex string" do
      assert SoundHelpers.text_on_bg("red") == :default
    end

    test "returns :dark_text for light 6-digit color" do
      assert SoundHelpers.text_on_bg("#ffffff") == :dark_text
    end

    test "returns :light_text for dark 6-digit color" do
      assert SoundHelpers.text_on_bg("#000000") == :light_text
    end

    test "expands 3-digit hex: #fff -> :dark_text" do
      assert SoundHelpers.text_on_bg("#fff") == :dark_text
    end

    test "expands 3-digit hex: #000 -> :light_text" do
      assert SoundHelpers.text_on_bg("#000") == :light_text
    end

    test "strips alpha from 8-digit hex: #ffffffff -> :dark_text" do
      assert SoundHelpers.text_on_bg("#ffffffff") == :dark_text
    end

    test "strips alpha from 8-digit hex: #000000ff -> :light_text" do
      assert SoundHelpers.text_on_bg("#000000ff") == :light_text
    end

    test "3-digit and 6-digit expansions agree for the same color" do
      assert SoundHelpers.text_on_bg("#fff") == SoundHelpers.text_on_bg("#ffffff")
      assert SoundHelpers.text_on_bg("#000") == SoundHelpers.text_on_bg("#000000")
    end

    test "8-digit and 6-digit agree when alpha is stripped" do
      assert SoundHelpers.text_on_bg("#ff0000ff") == SoundHelpers.text_on_bg("#ff0000")
    end
  end
end
