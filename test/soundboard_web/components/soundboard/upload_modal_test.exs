defmodule SoundboardWeb.Components.Soundboard.UploadModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SoundboardWeb.Components.Soundboard.UploadModal

  test "renders url workflow and prompts for missing URL" do
    html = render_component(&UploadModal.upload_modal/1, upload_assigns())

    assert html =~ "Add Sound"
    assert html =~ "Source Type"
    assert html =~ "Enter a URL first to name it."
  end

  test "renders filled URL workflow without missing-url helper text" do
    html =
      render_component(
        &UploadModal.upload_modal/1,
        upload_assigns(%{
          source_type: "url",
          url: "https://example.com/clip.mp3",
          upload_name: "clip"
        })
      )

    assert html =~ "upload-url-input"
    refute html =~ "Enter a URL first to name it."
  end

  test "disables submit when upload validation error is present" do
    html =
      render_component(
        &UploadModal.upload_modal/1,
        upload_assigns(%{
          source_type: "url",
          url: "https://example.com/clip.mp3",
          upload_name: "clip",
          upload_error: "URL is invalid"
        })
      )

    assert html =~ "disabled"
    assert html =~ "URL is invalid"
  end

  defp upload_assigns(overrides \\ %{}) do
    base = %{
      source_type: "url",
      uploads: %{audio: %{entries: []}},
      url: "",
      upload_name: "",
      upload_error: nil,
      upload_tags: [],
      upload_tag_input: "",
      upload_tag_suggestions: [],
      upload_volume: 100,
      is_join_sound: false,
      is_leave_sound: false
    }

    Map.merge(base, overrides)
  end
end
