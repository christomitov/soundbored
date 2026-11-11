defmodule SoundboardWeb.SoundHelpersTest do
  use ExUnit.Case, async: true
  alias SoundboardWeb.SoundHelpers

  test "display_name/1 drops directories and the extension" do
    assert SoundHelpers.display_name("priv/static/uploads/beep.mp3") == "beep"
    assert SoundHelpers.display_name("wow") == "wow"
  end

  test "slugify/1 makes a lower-case DOM-safe slug, or \"sound\" when nothing is left" do
    assert SoundHelpers.slugify("Wow Sound.MP3") == "wow-sound"
    assert SoundHelpers.slugify("日本.mp3") == "sound"
  end
end
