defmodule Soundboard.VolumeTest do
  use ExUnit.Case, async: true
  alias Soundboard.Volume

  describe "normalize_percent/2" do
    test "handles integers" do
      assert Volume.normalize_percent(75, 100) == 75
      assert Volume.normalize_percent(-5, 50) == 0
      assert Volume.normalize_percent(150, 50) == 150
    end

    test "handles strings and fallbacks" do
      assert Volume.normalize_percent("42", 100) == 42
      assert Volume.normalize_percent(" 84.5 ", 10) == 85
      assert Volume.normalize_percent("garbage", 30) == 30
    end
  end

  describe "percent_to_decimal/2" do
    test "converts to decimal with fallback" do
      assert Volume.percent_to_decimal("50", 100) == 0.5
      assert Volume.percent_to_decimal(nil, 80) == 0.8
      assert Volume.percent_to_decimal("110", 100) == 1.1
      assert Volume.percent_to_decimal("150", 100) == 1.5
      assert Volume.percent_to_decimal("200", 25) == 1.5
    end
  end

  describe "decimal_to_percent/1" do
    test "handles nil and bounds" do
      assert Volume.decimal_to_percent(nil) == 100
      assert Volume.decimal_to_percent(0.0625) == 6
      assert Volume.decimal_to_percent(0.64) == 64
      assert Volume.decimal_to_percent(1.1) == 110
      assert Volume.decimal_to_percent(1.4) == 140
      assert Volume.decimal_to_percent(1.6) == 150
      assert Volume.decimal_to_percent(-0.2) == 0
    end
  end
end
