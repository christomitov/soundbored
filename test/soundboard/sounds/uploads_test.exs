defmodule Soundboard.Sounds.UploadsTest do
  use Soundboard.DataCase

  import Soundboard.DataCase, only: [errors_on: 1]

  alias Soundboard.Accounts.User
  alias Soundboard.Sounds.Uploads
  alias Soundboard.{Repo, Sound, UserSoundSetting}

  setup do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "upload_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg"
      })
      |> Repo.insert()

    %{user: user}
  end

  describe "validate/1" do
    test "validates URL uploads when enough input is present", %{user: user} do
      assert {:ok, _params} =
               Uploads.validate(%{
                 user: user,
                 source_type: "url",
                 name: "validated_url",
                 url: "https://example.com/sound.mp3"
               })
    end

    test "requires a url for url uploads", %{user: user} do
      assert {:error, changeset} =
               Uploads.validate(%{
                 user: user,
                 source_type: "url",
                 name: "validated_url"
               })

      assert "can't be blank" in errors_on(changeset).url
    end

    test "rejects duplicate local filenames before copying", %{user: user} do
      {:ok, _existing} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "duplicate_name.mp3",
          source_type: "local",
          user_id: user.id
        })
        |> Repo.insert()

      assert {:error, changeset} =
               Uploads.validate(%{
                 user: user,
                 source_type: "local",
                 name: "duplicate_name",
                 upload: %{filename: "dup.mp3"}
               })

      assert "has already been taken" in errors_on(changeset).filename
    end

    test "requires a local file selection for local uploads", %{user: user} do
      assert {:error, changeset} =
               Uploads.validate(%{
                 user: user,
                 source_type: "local",
                 name: "missing_file"
               })

      assert "Please select a file" in errors_on(changeset).file
    end
  end

  describe "create/1" do
    test "creates url sound with tags and settings", %{user: user} do
      name = "upload_url_#{System.unique_integer([:positive])}"

      assert {:ok, sound} =
               Uploads.create(%{
                 user: user,
                 source_type: "url",
                 name: name,
                 url: "https://example.com/sound.mp3",
                 tags: ["alpha", "beta"],
                 volume: "45",
                 is_join_sound: "true"
               })

      assert sound.filename == "#{name}.mp3"
      assert sound.source_type == "url"
      assert_in_delta sound.volume, 0.45, 0.0001

      sound = Repo.preload(sound, :tags)
      assert Enum.sort(Enum.map(sound.tags, & &1.name)) == ["alpha", "beta"]

      setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: sound.id)
      assert setting.is_join_sound
      refute setting.is_leave_sound
    end

    test "publishes canonical soundboard events after create", %{user: user} do
      Soundboard.PubSubTopics.subscribe_files()
      Soundboard.PubSubTopics.subscribe_stats()

      name = "upload_events_#{System.unique_integer([:positive])}"

      assert {:ok, _sound} =
               Uploads.create(%{
                 user: user,
                 source_type: "url",
                 name: name,
                 url: "https://example.com/events.mp3"
               })

      assert_receive {:files_updated}
      assert_receive {:stats_updated}
    end

    test "copies local file and persists sound", %{user: user} do
      name = "upload_local_#{System.unique_integer([:positive])}"
      tmp_path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-local.wav")
      File.write!(tmp_path, "audio")

      on_exit(fn -> File.rm(tmp_path) end)

      assert {:ok, sound} =
               Uploads.create(%{
                 user: user,
                 source_type: "local",
                 name: name,
                 upload: %{path: tmp_path, filename: "local.wav"}
               })

      copied_path = Path.join(uploads_dir(), sound.filename)
      assert File.exists?(copied_path)

      on_exit(fn -> File.rm(copied_path) end)
    end

    test "clears previous join setting when creating a new join sound", %{user: user} do
      first_name = "first_join_#{System.unique_integer([:positive])}"
      second_name = "second_join_#{System.unique_integer([:positive])}"

      assert {:ok, first_sound} =
               Uploads.create(%{
                 user: user,
                 source_type: "url",
                 name: first_name,
                 url: "https://example.com/first.mp3",
                 is_join_sound: true
               })

      assert {:ok, second_sound} =
               Uploads.create(%{
                 user: user,
                 source_type: "url",
                 name: second_name,
                 url: "https://example.com/second.mp3",
                 is_join_sound: true
               })

      first_setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: first_sound.id)
      second_setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: second_sound.id)

      refute first_setting.is_join_sound
      assert second_setting.is_join_sound
    end

    test "returns error when local file is missing", %{user: user} do
      assert {:error, changeset} =
               Uploads.create(%{
                 user: user,
                 source_type: "local",
                 name: "missing_file"
               })

      assert "Please select a file" in errors_on(changeset).file
    end

    test "returns duplicate filename validation for local upload", %{user: user} do
      {:ok, _existing} =
        %Sound{}
        |> Sound.changeset(%{
          filename: "duplicate_name.mp3",
          source_type: "local",
          user_id: user.id
        })
        |> Repo.insert()

      tmp_path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-dup.mp3")
      File.write!(tmp_path, "audio")
      on_exit(fn -> File.rm(tmp_path) end)

      assert {:error, changeset} =
               Uploads.create(%{
                 user: user,
                 source_type: "local",
                 name: "duplicate_name",
                 upload: %{path: tmp_path, filename: "dup.mp3"}
               })

      assert "has already been taken" in errors_on(changeset).filename
    end
  end

  defp uploads_dir do
    Soundboard.UploadsPath.dir()
  end
end
