defmodule SoundboardWeb.Live.SoundboardLive.UploadFlowTest do
  use Soundboard.DataCase, async: true

  alias Phoenix.LiveView.Socket
  alias Soundboard.Tag
  alias SoundboardWeb.Live.SoundboardLive.UploadFlow

  test "select_tag adds a suggested tag even when it is outside the empty-search limit" do
    seed_alphabetical_tags()
    Repo.insert!(Tag.changeset(%Tag{}, %{name: "meme"}))

    socket = %Socket{assigns: %{__changed__: %{}, current_sound: nil, upload_tags: []}}

    assert {:noreply, updated_socket} = UploadFlow.select_tag(socket, "meme")

    assert Enum.map(updated_socket.assigns.upload_tags, & &1.name) == ["meme"]
    assert updated_socket.assigns.upload_tag_input == ""
    assert updated_socket.assigns.upload_tag_suggestions == []
  end

  defp seed_alphabetical_tags do
    for name <- ~w(a b c d e f g h i j) do
      Repo.insert!(Tag.changeset(%Tag{}, %{name: name}))
    end
  end
end
