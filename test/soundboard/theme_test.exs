defmodule Soundboard.ThemeTest do
  use ExUnit.Case, async: true

  alias Soundboard.Theme

  test "default is desk" do
    assert Theme.default() == "desk"
  end

  test "normalize accepts known themes" do
    assert Theme.normalize("classic") == "classic"
    assert Theme.normalize("desk") == "desk"
    assert Theme.normalize("retro") == "retro"
  end

  test "normalize falls back for unknown values" do
    assert Theme.normalize("neon") == "desk"
    assert Theme.normalize(nil) == "desk"
  end

  test "theme helpers" do
    assert Theme.desk?("desk")
    refute Theme.desk?("classic")
    assert Theme.classic?("classic")
    assert Theme.retro?("retro")
    refute Theme.retro?("desk")
  end
end
