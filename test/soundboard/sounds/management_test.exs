defmodule Soundboard.Sounds.ManagementTest do
  use Soundboard.DataCase

  alias Soundboard.Accounts.User
  alias Soundboard.Sounds.Management
  alias Soundboard.{Repo, Sound, UserSoundSetting}

  setup do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "mgmt_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    %{user: user}
  end

  test "delete_sound/2 removes local file and record", %{user: user} do
    filename = "delete_#{System.unique_integer([:positive])}.mp3"
    sound = insert_local_sound(user, filename)

    local_path = Path.join(uploads_dir(), filename)
    File.write!(local_path, "audio")
    on_exit(fn -> File.rm(local_path) end)
    assert File.exists?(local_path)

    assert :ok = Management.delete_sound(sound, user.id)

    refute File.exists?(local_path)
    assert Repo.get(Sound, sound.id) == nil
  end

  test "update_sound/3 renames local file and upserts user settings", %{user: user} do
    filename = "old_#{System.unique_integer([:positive])}.mp3"
    sound = insert_local_sound(user, filename)

    old_path = Path.join(uploads_dir(), filename)
    File.write!(old_path, "audio")
    on_exit(fn -> File.rm(old_path) end)

    params = %{
      "filename" => "renamed_#{System.unique_integer([:positive])}",
      "source_type" => "local",
      "url" => nil,
      "volume" => "80",
      "is_join_sound" => "true",
      "is_leave_sound" => "false"
    }

    assert {:ok, updated_sound} = Management.update_sound(sound, user.id, params)

    new_filename = params["filename"] <> ".mp3"
    new_path = Path.join(uploads_dir(), new_filename)
    on_exit(fn -> File.rm(new_path) end)

    assert updated_sound.filename == new_filename
    assert File.exists?(new_path)
    refute File.exists?(old_path)

    setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: updated_sound.id)
    assert setting.is_join_sound
    refute setting.is_leave_sound
  end

  test "update_sound/3 keeps sound metadata collaborative while preserving uploader ownership", %{
    user: user
  } do
    filename = "shared_#{System.unique_integer([:positive])}.mp3"
    sound = insert_local_sound(user, filename)

    old_path = Path.join(uploads_dir(), filename)
    File.write!(old_path, "audio")
    on_exit(fn -> File.rm(old_path) end)

    {:ok, editor} =
      %User{}
      |> User.changeset(%{
        username: "editor_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    params = %{
      "filename" => "edited_by_other_#{System.unique_integer([:positive])}",
      "source_type" => "local",
      "url" => nil,
      "volume" => "65",
      "is_join_sound" => "true",
      "is_leave_sound" => "false"
    }

    assert {:ok, updated_sound} = Management.update_sound(sound, editor.id, params)

    new_filename = params["filename"] <> ".mp3"
    new_path = Path.join(uploads_dir(), new_filename)
    on_exit(fn -> File.rm(new_path) end)

    assert updated_sound.filename == new_filename
    assert updated_sound.user_id == user.id
    assert File.exists?(new_path)
    refute File.exists?(old_path)

    setting = Repo.get_by!(UserSoundSetting, user_id: editor.id, sound_id: updated_sound.id)
    assert setting.is_join_sound
    refute setting.is_leave_sound
  end

  test "delete_sound/2 stays owner-only even when metadata edits are collaborative", %{user: user} do
    sound = insert_local_sound(user, "locked_#{System.unique_integer([:positive])}.mp3")

    {:ok, intruder} =
      %User{}
      |> User.changeset(%{
        username: "delete_intruder_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    assert {:error, :forbidden} = Management.delete_sound(sound, intruder.id)
    assert Repo.get!(Sound, sound.id)
  end

  defp insert_local_sound(user, filename) do
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: filename,
        source_type: "local",
        user_id: user.id,
        volume: 1.0
      })
      |> Repo.insert()

    sound
  end

  defp uploads_dir do
    Soundboard.UploadsPath.dir()
  end
end
