defmodule Soundboard.AudioPlayer.SoundLibraryTest do
  use Soundboard.DataCase

  alias Soundboard.Accounts.User
  alias Soundboard.AudioPlayer.SoundLibrary
  alias Soundboard.{Repo, Sound}

  setup do
    clear_sound_cache()

    on_exit(fn ->
      clear_sound_cache()
    end)

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "library_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    %{user: user}
  end

  test "ensure_cache/0 creates the cache table and is idempotent" do
    assert :undefined == :ets.whereis(:sound_meta_cache)

    assert :ok = SoundLibrary.ensure_cache()
    refute :undefined == :ets.whereis(:sound_meta_cache)

    assert :ok = SoundLibrary.ensure_cache()
  end

  test "get_sound_path/1 resolves and caches URL sounds", %{user: user} do
    sound =
      insert_sound!(user, %{
        filename: unique_filename("remote", ".mp3"),
        source_type: "url",
        url: "https://example.com/wow.mp3",
        volume: 0.8
      })

    assert {:ok, {"https://example.com/wow.mp3", 0.8}} =
             SoundLibrary.get_sound_path(sound.filename)

    Repo.delete!(sound)

    assert {:ok, {"https://example.com/wow.mp3", 0.8}} =
             SoundLibrary.get_sound_path(sound.filename)
  end

  test "get_sound_path/1 resolves local sounds when the file exists", %{user: user} do
    filename = unique_filename("local", ".wav")
    path = Soundboard.UploadsPath.file_path(filename)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "audio")
    on_exit(fn -> File.rm(path) end)

    sound = insert_sound!(user, %{filename: filename, source_type: "local", volume: 1.2})

    assert {:ok, {^path, 1.2}} = SoundLibrary.get_sound_path(sound.filename)
  end

  test "get_sound_path/1 returns helpful errors for missing local files", %{user: user} do
    filename = unique_filename("missing", ".mp3")
    sound = insert_sound!(user, %{filename: filename, source_type: "local"})

    assert {:error, message} = SoundLibrary.get_sound_path(sound.filename)
    assert message == "Sound file not found at #{Soundboard.UploadsPath.file_path(filename)}"
  end

  test "get_sound_path/1 returns error when the sound is missing" do
    assert {:error, "Sound not found"} = SoundLibrary.get_sound_path("missing.mp3")
  end

  test "prepare_play_input/2 prefers cached source metadata", %{user: user} do
    sound =
      insert_sound!(user, %{
        filename: unique_filename("cached", ".mp3"),
        source_type: "url",
        url: "https://example.com/cached.mp3"
      })

    assert {:ok, {"https://example.com/cached.mp3", 1.0}} =
             SoundLibrary.get_sound_path(sound.filename)

    assert {"play-this", :url} = SoundLibrary.prepare_play_input(sound.filename, "play-this")
  end

  test "prepare_play_input/2 falls back to the database when cache is empty", %{user: user} do
    sound =
      insert_sound!(user, %{
        filename: unique_filename("db", ".mp3"),
        source_type: "url",
        url: "https://example.com/db.mp3"
      })

    assert {"from-db", :url} = SoundLibrary.prepare_play_input(sound.filename, "from-db")
  end

  test "invalidate_cache/1 deletes cached entries and ignores non-binary input", %{user: user} do
    sound =
      insert_sound!(user, %{
        filename: unique_filename("invalidate", ".mp3"),
        source_type: "url",
        url: "https://example.com/invalidate.mp3"
      })

    assert {:ok, {"https://example.com/invalidate.mp3", 1.0}} =
             SoundLibrary.get_sound_path(sound.filename)

    assert [{_, _}] = :ets.lookup(:sound_meta_cache, sound.filename)

    assert :ok = SoundLibrary.invalidate_cache(sound.filename)
    assert [] == :ets.lookup(:sound_meta_cache, sound.filename)

    assert :ok = SoundLibrary.invalidate_cache(nil)
  end

  defp insert_sound!(user, attrs) do
    attrs =
      attrs
      |> Map.put_new(:user_id, user.id)
      |> Map.put_new(:volume, 1.0)

    %Sound{}
    |> Sound.changeset(attrs)
    |> Repo.insert!()
  end

  defp unique_filename(prefix, ext) do
    "#{prefix}_#{System.unique_integer([:positive])}#{ext}"
  end

  defp clear_sound_cache do
    case :ets.whereis(:sound_meta_cache) do
      :undefined -> :ok
      _table -> :ets.delete(:sound_meta_cache)
    end
  end
end
