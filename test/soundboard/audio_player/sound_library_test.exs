defmodule Soundboard.AudioPlayer.SoundLibraryTest do
  use Soundboard.DataCase, async: false

  @moduletag :capture_log

  alias Soundboard.Accounts.User
  alias Soundboard.AudioPlayer.SoundLibrary
  alias Soundboard.Sound

  setup do
    user =
      %User{}
      |> User.changeset(%{
        username: "library_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert!()

    %{user: user, guild: "library-#{System.unique_integer([:positive])}"}
  end

  test "URL sounds are cached per guild until invalidated", %{user: user, guild: guild} do
    other_guild = "#{guild}-other"
    sound = insert_sound!(user, guild, %{source_type: "url", url: "https://a.example/1.mp3"})

    assert {:ok, {"https://a.example/1.mp3", 0.8}} =
             SoundLibrary.get_sound_path(guild, sound.filename)

    assert {:error, "Sound not found"} = SoundLibrary.get_sound_path(other_guild, sound.filename)

    Repo.update!(Ecto.Changeset.change(sound, url: "https://a.example/2.mp3"))

    assert {:ok, {"https://a.example/1.mp3", 0.8}} =
             SoundLibrary.get_sound_path(guild, sound.filename)

    assert :ok = SoundLibrary.invalidate_cache(guild, sound.filename)

    assert {:ok, {"https://a.example/2.mp3", 0.8}} =
             SoundLibrary.get_sound_path(guild, sound.filename)
  end

  test "local sounds resolve to their uploaded file", %{user: user, guild: guild} do
    sound = insert_sound!(user, guild, %{source_type: "local", volume: 1.2})

    storage_path = Soundboard.UploadsPath.file_path(sound.storage_key)
    File.mkdir_p!(Path.dirname(storage_path))
    File.write!(storage_path, "audio")
    on_exit(fn -> File.rm(storage_path) end)

    assert {:ok, {^storage_path, 1.2}} = SoundLibrary.get_sound_path(guild, sound.filename)
  end

  defp insert_sound!(user, guild, attrs) do
    attrs =
      Map.merge(
        %{
          filename: "sound_#{System.unique_integer([:positive])}.mp3",
          user_id: user.id,
          guild_id: guild,
          volume: 0.8
        },
        attrs
      )

    %Sound{}
    |> Sound.changeset(attrs)
    |> Repo.insert!()
  end
end
