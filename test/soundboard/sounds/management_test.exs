defmodule Soundboard.Sounds.ManagementTest do
  use Soundboard.DataCase

  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Sound, UserSoundSetting}
  alias Soundboard.Sounds.Management

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

    # File lives at storage_key path, not display filename path
    storage_path = Path.join(uploads_dir(), sound.storage_key)
    File.write!(storage_path, "audio")
    on_exit(fn -> File.rm(storage_path) end)
    assert File.exists?(storage_path)

    with_mock Soundboard.AudioPlayer, invalidate_cache: fn ^filename -> :ok end do
      assert :ok = Management.delete_sound(sound, user.id)
      assert_called(Soundboard.AudioPlayer.invalidate_cache(filename))
    end

    refute File.exists?(storage_path)
    assert Repo.get(Sound, sound.id) == nil
  end

  test "update_sound/3 updates display name without moving the file", %{user: user} do
    filename = "old_#{System.unique_integer([:positive])}.mp3"
    sound = insert_local_sound(user, filename)

    # File lives at storage_key path — rename does not move it
    storage_path = Path.join(uploads_dir(), sound.storage_key)
    File.write!(storage_path, "audio")
    on_exit(fn -> File.rm(storage_path) end)

    params = %{
      "filename" => "renamed_#{System.unique_integer([:positive])}",
      "source_type" => "local",
      "url" => nil,
      "volume" => "80",
      "is_join_sound" => "true",
      "is_leave_sound" => "false"
    }

    new_filename = params["filename"] <> ".mp3"

    with_mock Soundboard.AudioPlayer,
      invalidate_cache: fn cache_key when cache_key in [filename, new_filename] -> :ok end do
      assert {:ok, updated_sound} = Management.update_sound(sound, user.id, params)

      assert_called(Soundboard.AudioPlayer.invalidate_cache(filename))
      assert_called(Soundboard.AudioPlayer.invalidate_cache(new_filename))

      # Display name updated; storage_key (and file on disk) unchanged
      assert updated_sound.filename == new_filename
      assert updated_sound.storage_key == sound.storage_key
      assert File.exists?(storage_path)

      setting = Repo.get_by!(UserSoundSetting, user_id: user.id, sound_id: updated_sound.id)
      assert setting.is_join_sound
      refute setting.is_leave_sound
    end
  end

  test "update_sound/3 keeps sound metadata collaborative while preserving uploader ownership", %{
    user: user
  } do
    filename = "shared_#{System.unique_integer([:positive])}.mp3"
    sound = insert_local_sound(user, filename)

    storage_path = Path.join(uploads_dir(), sound.storage_key)
    File.write!(storage_path, "audio")
    on_exit(fn -> File.rm(storage_path) end)

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

    assert updated_sound.filename == new_filename
    assert updated_sound.user_id == user.id
    assert updated_sound.storage_key == sound.storage_key
    assert File.exists?(storage_path)

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

  test "update_sound/3 deletes old image file when replaced with a new one", %{user: user} do
    filename = "img_#{System.unique_integer([:positive])}.mp3"
    old_image = "old_#{System.unique_integer([:positive])}.png"
    new_image = "new_#{System.unique_integer([:positive])}.png"

    sound = insert_local_sound(user, filename, image_filename: old_image)

    storage_path = Path.join(uploads_dir(), sound.storage_key)
    images_dir = Path.join(uploads_dir(), "images")
    old_image_path = Path.join(images_dir, old_image)

    File.mkdir_p!(images_dir)
    File.write!(storage_path, "audio")
    File.write!(old_image_path, "old_image_data")

    on_exit(fn ->
      File.rm(storage_path)
      File.rm(old_image_path)
    end)

    params = %{
      "filename" => "img_renamed_#{System.unique_integer([:positive])}",
      "source_type" => "local",
      "url" => nil,
      "volume" => "80",
      "is_join_sound" => "false",
      "is_leave_sound" => "false",
      "image_filename" => new_image
    }

    assert {:ok, updated_sound} = Management.update_sound(sound, user.id, params)
    assert updated_sound.image_filename == new_image
    refute File.exists?(old_image_path)
  end

  test "update_sound/3 deletes image file when cleared", %{user: user} do
    filename = "clear_img_#{System.unique_integer([:positive])}.mp3"
    old_image = "to_clear_#{System.unique_integer([:positive])}.png"

    sound = insert_local_sound(user, filename, image_filename: old_image)

    storage_path = Path.join(uploads_dir(), sound.storage_key)
    images_dir = Path.join(uploads_dir(), "images")
    old_image_path = Path.join(images_dir, old_image)

    File.mkdir_p!(images_dir)
    File.write!(storage_path, "audio")
    File.write!(old_image_path, "image_data")

    on_exit(fn ->
      File.rm(storage_path)
      File.rm(old_image_path)
    end)

    params = %{
      "filename" => "clear_img_renamed_#{System.unique_integer([:positive])}",
      "source_type" => "local",
      "url" => nil,
      "volume" => "80",
      "is_join_sound" => "false",
      "is_leave_sound" => "false",
      "clear_image" => "true"
    }

    assert {:ok, updated_sound} = Management.update_sound(sound, user.id, params)
    assert updated_sound.image_filename == nil
    refute File.exists?(old_image_path)
  end

  test "update_sound/3 cleans up new image file when DB update fails", %{user: user} do
    sound1 = insert_local_sound(user, "conflict_a_#{System.unique_integer([:positive])}.mp3")
    sound2 = insert_local_sound(user, "conflict_b_#{System.unique_integer([:positive])}.mp3")

    storage_path = Path.join(uploads_dir(), sound1.storage_key)
    File.write!(storage_path, "audio")
    on_exit(fn -> File.rm(storage_path) end)

    images_dir = Path.join(uploads_dir(), "images")
    new_image = "new_img_#{System.unique_integer([:positive])}.png"
    new_image_path = Path.join(images_dir, new_image)
    File.mkdir_p!(images_dir)
    File.write!(new_image_path, "image_data")
    on_exit(fn -> File.rm(new_image_path) end)

    # Rename sound1 to sound2's filename — triggers unique constraint failure
    conflicting_name = Path.rootname(sound2.filename)

    params = %{
      "filename" => conflicting_name,
      "source_type" => "local",
      "url" => nil,
      "volume" => "80",
      "is_join_sound" => "false",
      "is_leave_sound" => "false",
      "image_filename" => new_image
    }

    assert {:error, _} = Management.update_sound(sound1, user.id, params)
    refute File.exists?(new_image_path)
  end

  defp insert_local_sound(user, filename, opts \\ []) do
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: filename,
        source_type: "local",
        user_id: user.id,
        volume: 1.0,
        image_filename: Keyword.get(opts, :image_filename)
      })
      |> Repo.insert()

    sound
  end

  defp uploads_dir do
    Soundboard.UploadsPath.dir()
  end
end
