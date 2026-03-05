defmodule SoundboardWeb.Components.Soundboard.EditModalTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SoundboardWeb.Components.Soundboard.EditModal

  test "renders edit form with local file metadata" do
    html = render_component(&EditModal.edit_modal/1, edit_assigns())

    assert html =~ "Edit Sound"
    assert html =~ "Local File"
    assert html =~ "Save Changes"
    assert html =~ "Delete Sound"
  end

  test "renders source URL and flash validation errors" do
    html =
      render_component(
        &EditModal.edit_modal/1,
        edit_assigns(%{
          current_sound: %{
            edit_sound()
            | source_type: "url",
              url: "https://example.com/sound.mp3"
          },
          flash: %{error: "Name already taken"}
        })
      )

    assert html =~ "URL: https://example.com/sound.mp3"
    assert html =~ "Name already taken"
  end

  defp edit_assigns(overrides \\ %{}) do
    base = %{
      current_sound: edit_sound(),
      current_user: %{id: 1},
      tag_input: "",
      tag_suggestions: [],
      validation_error: nil,
      flash: %{}
    }

    Map.merge(base, overrides)
  end

  defp edit_sound do
    %{
      id: 10,
      filename: "laser.mp3",
      source_type: "local",
      url: nil,
      volume: 1.0,
      tags: [%{name: "funny"}],
      user_id: 1,
      user_sound_settings: [%{user_id: 1, is_join_sound: true, is_leave_sound: false}]
    }
  end
end
