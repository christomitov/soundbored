defmodule SoundboardWeb.ErrorJSONTest do
  use SoundboardWeb.ConnCase, async: true

  test "renders 404" do
    assert SoundboardWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert SoundboardWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
