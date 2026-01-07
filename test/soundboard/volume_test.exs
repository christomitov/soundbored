defmodule Soundboard.VolumeTest do
  use ExUnit.Case, async: true

  alias Soundboard.Volume

  test "clamp_percent bounds values between 0 and 150" do
    assert Volume.clamp_percent(-5) == 0
    assert Volume.clamp_percent(101.8) == 102
    assert Volume.clamp_percent(300) == 150
  end

  test "percent_to_decimal handles boosted and muted volumes" do
    assert Volume.percent_to_decimal(0) == 0.0
    assert Volume.percent_to_decimal(50) == 0.5
    assert Volume.percent_to_decimal(125) == 1.25
  end

  test "normalize_percent falls back to defaults on invalid input" do
    assert Volume.normalize_percent("not-a-number", 75) == 75
    assert Volume.normalize_percent(nil, 40) == 40
    assert Volume.normalize_percent("140", 10) == 140
  end

  test "decimal_to_percent clamps and expands boosted values" do
    assert Volume.decimal_to_percent(nil) == 100
    assert Volume.decimal_to_percent(-1.0) == 0
    assert Volume.decimal_to_percent(0.25) == 25
    assert Volume.decimal_to_percent(1.25) == 125
    assert Volume.decimal_to_percent(5.0) == 150
  end
end
