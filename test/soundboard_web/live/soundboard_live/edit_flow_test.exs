defmodule SoundboardWeb.Live.SoundboardLive.EditFlowTest do
  use Soundboard.DataCase, async: true

  alias Phoenix.LiveView.Socket
  alias Soundboard.Accounts.User
  alias Soundboard.{Sound, Tag}
  alias SoundboardWeb.Live.SoundboardLive.EditFlow

  test "select_tag adds a suggested tag even when it is outside the empty-search limit" do
    seed_alphabetical_tags()
    tag = Repo.insert!(Tag.changeset(%Tag{}, %{name: "meme"}))
    user = create_user()

    sound =
      %Sound{}
      |> Sound.changeset(%{filename: "test.mp3", source_type: "local", user_id: user.id})
      |> Repo.insert!()
      |> Repo.preload(:tags)

    socket = %Socket{assigns: %{__changed__: %{}, current_sound: sound}}

    assert {:noreply, updated_socket} = EditFlow.select_tag(socket, "meme")

    assert Enum.any?(updated_socket.assigns.current_sound.tags, &(&1.id == tag.id))
    assert updated_socket.assigns.tag_input == ""
    assert updated_socket.assigns.tag_suggestions == []
  end

  defp create_user do
    %User{}
    |> User.changeset(%{
      username: "testuser",
      discord_id: Integer.to_string(System.unique_integer([:positive])),
      avatar: "avatar.png"
    })
    |> Repo.insert!()
  end

  defp seed_alphabetical_tags do
    for name <- ~w(a b c d e f g h i j) do
      Repo.insert!(Tag.changeset(%Tag{}, %{name: name}))
    end
  end
end
