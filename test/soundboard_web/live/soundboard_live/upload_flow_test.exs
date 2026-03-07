defmodule SoundboardWeb.Live.SoundboardLive.UploadFlowTest do
  use Soundboard.DataCase, async: true

  alias Phoenix.LiveView.Socket
  alias Soundboard.Tag
  alias SoundboardWeb.Live.SoundboardLive.UploadFlow

  test "select_tag adds a suggested tag even when it is outside the empty-search limit" do
    seed_alphabetical_tags()
    Repo.insert!(Tag.changeset(%Tag{}, %{name: "meme"}))

    socket = build_socket(%{current_sound: nil, upload_tags: []})

    assert {:noreply, updated_socket} = UploadFlow.select_tag(socket, "meme")

    assert Enum.map(updated_socket.assigns.upload_tags, & &1.name) == ["meme"]
    assert updated_socket.assigns.upload_tag_input == ""
    assert updated_socket.assigns.upload_tag_suggestions == []
  end

  test "save treats consume_uploaded_entries success results as a successful upload" do
    socket = build_socket(%{show_upload_modal: true})

    consume_uploaded_entries_fn = fn _socket, :audio, _fun ->
      [{:ok, %{id: 123}}]
    end

    assert {:noreply, updated_socket} = UploadFlow.save(socket, %{}, consume_uploaded_entries_fn)

    assert updated_socket.assigns.show_upload_modal == false
    assert updated_socket.assigns.flash["info"] == "Sound added successfully"
    assert is_list(updated_socket.assigns.uploaded_files)
  end

  test "save shows upload errors returned by consume_uploaded_entries" do
    socket = build_socket(%{show_upload_modal: true})

    changeset =
      %Ecto.Changeset{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:filename, "can't be blank")

    consume_uploaded_entries_fn = fn _socket, :audio, _fun ->
      [{:error, changeset}]
    end

    assert {:noreply, updated_socket} = UploadFlow.save(socket, %{}, consume_uploaded_entries_fn)

    assert updated_socket.assigns.show_upload_modal == true
    assert updated_socket.assigns.flash["error"] == "filename can't be blank"
  end

  defp build_socket(overrides) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            current_sound: nil,
            show_upload_modal: false,
            source_type: "local",
            upload_name: "",
            url: "",
            upload_tags: [],
            upload_tag_input: "",
            upload_tag_suggestions: [],
            is_join_sound: false,
            is_leave_sound: false,
            upload_error: nil,
            upload_volume: 100
          },
          overrides
        ),
      private: %{live_temp: %{flash: %{}}}
    }
  end

  defp seed_alphabetical_tags do
    for name <- ~w(a b c d e f g h i j) do
      Repo.insert!(Tag.changeset(%Tag{}, %{name: name}))
    end
  end
end
