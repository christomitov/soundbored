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
  end

  describe "slugify/1" do
    test "converts filename to lower-case slug" do
      assert SoundHelpers.slugify("Wow Sound.MP3") == "wow-sound"
    end

    test "falls back to default" do
      assert SoundHelpers.slugify(nil) == "sound"
    end
  end
end
