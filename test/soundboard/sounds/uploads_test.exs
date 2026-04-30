defmodule Soundboard.Sounds.UploadsTest do
  use Soundboard.DataCase

  import Soundboard.DataCase, only: [errors_on: 1]

  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Sound, UserSoundSetting}
  alias Soundboard.Sounds.Uploads
  alias Soundboard.Sounds.Uploads.{CreateRequest, Source}

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
               user
               |> request(%{
                 source_type: "url",
                 name: "validated_url",
                 url: "https://example.com/sound.mp3"
               })
               |> Uploads.validate()
    end

    test "requires a url for url uploads", %{user: user} do
      assert {:error, changeset} =
               user
               |> request(%{
                 source_type: "url",
                 name: "validated_url"
               })
               |> Uploads.validate()

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
               user
               |> request(%{
                 source_type: "local",
                 name: "duplicate_name",
                 upload: %{filename: "dup.mp3"}
               })
               |> Uploads.validate()

      assert "has already been taken" in errors_on(changeset).filename
    end

    test "requires a local file selection for local uploads", %{user: user} do
      assert {:error, changeset} =
               user
               |> request(%{
                 source_type: "local",
                 name: "missing_file"
               })
               |> Uploads.validate()

      assert "Please select a file" in errors_on(changeset).file
    end
  end

  describe "create/1" do
    test "creates url sound with tags and settings", %{user: user} do
      name = "upload_url_#{System.unique_integer([:positive])}"

      assert {:ok, sound} =
               user
               |> request(%{
                 source_type: "url",
                 name: name,
                 url: "https://example.com/sound.mp3",
                 tags: ["alpha", "beta"],
                 volume: "45",
                 is_join_sound: "true"
               })
               |> Uploads.create()

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
               user
               |> request(%{
                 source_type: "url",
                 name: name,
                 url: "https://example.com/events.mp3"
               })
               |> Uploads.create()

      assert_receive {:files_updated}
      assert_receive {:stats_updated}
    end

    test "copies local file and persists sound", %{user: user} do
      name = "upload_local_#{System.unique_integer([:positive])}"
      tmp_path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-local.mp3")
      File.cp!(Soundboard.TestHelpers.audio_fixture_path(), tmp_path)

      on_exit(fn -> File.rm(tmp_path) end)

      assert {:ok, sound} =
               user
               |> request(%{
                 source_type: "local",
                 name: name,
                 upload: %{path: tmp_path, filename: "local.mp3"}
               })
               |> Uploads.create()

      copied_path = Path.join(uploads_dir(), sound.storage_key)
      assert File.exists?(copied_path)

      on_exit(fn -> File.rm(copied_path) end)
    end

    test "clears previous join setting when creating a new join sound", %{user: user} do
      first_name = "first_join_#{System.unique_integer([:positive])}"
      second_name = "second_join_#{System.unique_integer([:positive])}"

      assert {:ok, first_sound} =
               user
               |> request(%{
                 source_type: "url",
                 name: first_name,
                 url: "https://example.com/first.mp3",
                 is_join_sound: true
               })
               |> Uploads.create()

      assert {:ok, second_sound} =
               user
               |> request(%{
                 source_type: "url",
                 name: second_name,
                 url: "https://example.com/second.mp3",
                 is_join_sound: true
               })
               |> Uploads.create()

      first_setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: first_sound.id)
      second_setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: second_sound.id)

      refute first_setting.is_join_sound
      assert second_setting.is_join_sound
    end

    test "returns error when local file is missing", %{user: user} do
      assert {:error, changeset} =
               user
               |> request(%{
                 source_type: "local",
                 name: "missing_file"
               })
               |> Uploads.create()

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
      File.cp!(Soundboard.TestHelpers.audio_fixture_path(), tmp_path)
      on_exit(fn -> File.rm(tmp_path) end)

      assert {:error, changeset} =
               user
               |> request(%{
                 source_type: "local",
                 name: "duplicate_name",
                 upload: %{path: tmp_path, filename: "dup.mp3"}
               })
               |> Uploads.create()

      assert "has already been taken" in errors_on(changeset).filename
    end
  end

  describe "name sanitization" do
    test "strips forward slashes from name", %{user: user} do
      n = System.unique_integer([:positive])

      assert {:ok, sound} =
               user
               |> request(%{
                 source_type: "url",
                 name: "../../evil/sound_#{n}",
                 url: "https://example.com/test.mp3"
               })
               |> Uploads.create()

      refute String.contains?(sound.filename, "/")
    end

    test "strips backslashes from name", %{user: user} do
      n = System.unique_integer([:positive])

      assert {:ok, sound} =
               user
               |> request(%{
                 source_type: "url",
                 name: "some\\evil\\#{n}",
                 url: "https://example.com/test.mp3"
               })
               |> Uploads.create()

      refute String.contains?(sound.filename, "\\")
    end

    test "strips null bytes from name", %{user: user} do
      n = System.unique_integer([:positive])

      assert {:ok, sound} =
               user
               |> request(%{
                 source_type: "url",
                 name: "some\0evil\0#{n}",
                 url: "https://example.com/test.mp3"
               })
               |> Uploads.create()

      refute String.contains?(sound.filename, "\0")
    end

    test "trims leading and trailing whitespace", %{user: user} do
      n = System.unique_integer([:positive])

      assert {:ok, sound} =
               user
               |> request(%{
                 source_type: "url",
                 name: "  trimmed #{n}  ",
                 url: "https://example.com/test.mp3"
               })
               |> Uploads.create()

      assert sound.filename == "trimmed #{n}.mp3"
    end

    test "truncates name to 200 characters", %{user: user} do
      long_name = String.duplicate("a", 210)

      assert {:ok, sound} =
               user
               |> request(%{
                 source_type: "url",
                 name: long_name,
                 url: "https://example.com/test.mp3"
               })
               |> Uploads.create()

      assert String.length(Path.rootname(sound.filename)) == 200
    end

    test "returns error when name is blank after stripping", %{user: user} do
      assert {:error, changeset} =
               user
               |> request(%{
                 source_type: "url",
                 name: "///",
                 url: "https://example.com/test.mp3"
               })
               |> Uploads.validate()

      assert "can't be blank" in errors_on(changeset).filename
    end

    test "returns error for nil name", %{user: user} do
      assert {:error, changeset} =
               user
               |> request(%{
                 source_type: "url",
                 name: nil,
                 url: "https://example.com/test.mp3"
               })
               |> Uploads.validate()

      assert "can't be blank" in errors_on(changeset).filename
    end

    test "strips path separators in local upload name", %{user: user} do
      n = System.unique_integer([:positive])
      tmp_path = Path.join(System.tmp_dir!(), "#{n}.wav")
      File.cp!(Soundboard.TestHelpers.audio_fixture_path(), tmp_path)
      on_exit(fn -> File.rm(tmp_path) end)

      assert {:ok, sound} =
               user
               |> request(%{
                 source_type: "local",
                 name: "../escape_#{n}",
                 upload: %{path: tmp_path, filename: "test.wav"}
               })
               |> Uploads.create()

      refute String.contains?(sound.filename, "/")
      on_exit(fn -> File.rm(Soundboard.UploadsPath.file_path(sound.filename)) end)
    end
  end

  describe "Source.prepare/2" do
    test "returns error for invalid source_type" do
      assert {:error, changeset} =
               Source.prepare(%{source_type: "youtube", name: "test"}, :validate)

      assert "must be either 'local' or 'url'" in errors_on(changeset).source_type
    end

    test "returns error when url is nil" do
      assert {:error, changeset} =
               Source.prepare(%{source_type: "url", url: nil, name: "test"}, :validate)

      assert "can't be blank" in errors_on(changeset).url
    end

    test "returns error for blank filename in local upload in validate mode" do
      assert {:error, changeset} =
               Source.prepare(
                 %{source_type: "local", upload: %{filename: "", path: nil}, name: "test"},
                 :validate
               )

      assert "Please select a file" in errors_on(changeset).file
    end

    test "returns error for blank filename in local upload in create mode" do
      assert {:error, changeset} =
               Source.prepare(
                 %{
                   source_type: "local",
                   upload: %{filename: "", path: "/some/path"},
                   name: "test"
                 },
                 :create
               )

      assert "Invalid file upload" in errors_on(changeset).file
    end

    test "returns error when local upload is not a recognized struct in create mode" do
      assert {:error, changeset} =
               Source.prepare(
                 %{
                   source_type: "local",
                   upload: %{path: 123, filename: "test.mp3"},
                   name: "test"
                 },
                 :create
               )

      assert "Please select a file" in errors_on(changeset).file
    end

    test "handles url with no path component (nil URI path)" do
      assert {:ok, source} =
               Source.prepare(
                 %{source_type: "url", url: "http://example.com", name: "nopathtest"},
                 :validate
               )

      assert source.filename == "nopathtest"
    end
  end

  describe "Source.cleanup_local_file/1" do
    test "returns :ok when file does not exist (error branch)" do
      assert :ok =
               Source.cleanup_local_file(
                 "/tmp/soundbored_nonexistent_#{System.unique_integer()}.mp3"
               )
    end

    test "returns :ok for nil input" do
      assert :ok = Source.cleanup_local_file(nil)
    end
  end

  defp request(user, attrs) do
    CreateRequest.new(user, attrs)
  end

  defp uploads_dir do
    Soundboard.UploadsPath.dir()
  end
end
