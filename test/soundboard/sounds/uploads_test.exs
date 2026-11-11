defmodule Soundboard.Sounds.UploadsTest do
  @moduledoc """
  What the upload context promises beyond the API's create contracts (which
  live in `SoundboardWeb.API.SoundControllerTest`): every open soundboard
  hears about a new sound, and its errors read as sentences in the upload
  form.
  """

  use Soundboard.DataCase, async: false

  alias Soundboard.Accounts.User
  alias Soundboard.Repo
  alias Soundboard.Sounds.Uploads
  alias Soundboard.Sounds.Uploads.CreateRequest

  setup do
    %{user: Repo.insert!(%User{discord_id: "uploader", username: "uploader"})}
  end

  test "a created sound is announced to open soundboards and stats", %{user: user} do
    Soundboard.PubSubTopics.subscribe_files()
    Soundboard.PubSubTopics.subscribe_stats()

    assert {:ok, _sound} =
             user
             |> CreateRequest.new(%{name: "announced", url: "https://example.com/events.mp3"})
             |> Uploads.create()

    assert_receive {:files_updated}
    assert_receive {:stats_updated}
  end

  describe "error_message/1" do
    test "shows a whole-sound error as the message alone", %{user: user} do
      {:ok, _} = Soundboard.Tenants.get_or_create_guild("no-plan", %{max_storage_bytes: 0})

      assert {:error, changeset} =
               user
               |> CreateRequest.new(%{
                 name: "blocked",
                 url: "https://example.com/b.mp3",
                 guild_id: "no-plan"
               })
               |> Uploads.create()

      assert Uploads.error_message(changeset) ==
               "This soundboard has no active plan. Subscribe to add sounds."
    end

    test "shows a file error as its sentence alone", %{user: user} do
      assert {:error, changeset} =
               user
               |> CreateRequest.new(%{name: "notes"})
               |> CreateRequest.put_upload(%{path: "/tmp/notes.txt", filename: "notes.txt"})
               |> Uploads.create()

      assert Uploads.error_message(changeset) ==
               "Invalid file type. Please upload an MP3, WAV, OGG, or M4A file."
    end
  end
end
