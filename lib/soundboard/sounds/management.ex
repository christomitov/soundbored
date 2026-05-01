defmodule Soundboard.Sounds.Management do
  @moduledoc """
  Domain-level sound update/delete operations used by LiveViews.

  Sound metadata edits are collaborative for signed-in users, while deletion
  remains restricted to the original uploader. Per-user join/leave preferences
  are stored separately so editors keep their own settings without taking over
  sound ownership.
  """

  alias Soundboard.{AudioPlayer, Repo, Sound, UploadsPath, Volume}
  alias Soundboard.Sounds.ImageProcessing
  require Logger

  def update_sound(%Sound{} = sound, user_id, params) do
    Repo.transaction(fn ->
      db_sound =
        Repo.get!(Sound, sound.id)
        |> Repo.preload(:user_sound_settings)

      sound_params = build_sound_params(db_sound, user_id, params)

      case Sound.changeset(db_sound, sound_params) |> Repo.update() do
        {:ok, updated_sound} ->
          maybe_delete_old_image(params, db_sound)
          updated_sound = update_user_settings(db_sound, user_id, updated_sound, params)
          AudioPlayer.invalidate_cache(db_sound.filename)
          AudioPlayer.invalidate_cache(updated_sound.filename)
          updated_sound

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def delete_sound(%Sound{} = sound, user_id) do
    db_sound = Repo.get!(Sound, sound.id)

    with true <- db_sound.user_id == user_id,
         {:ok, _deleted_sound} <- Repo.delete(db_sound) do
      AudioPlayer.invalidate_cache(db_sound.filename)
      maybe_remove_local_file(db_sound)
      ImageProcessing.delete_image(db_sound.image_filename)
      :ok
    else
      false -> {:error, :forbidden}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp build_sound_params(db_sound, user_id, params) do
    %{
      filename: params["filename"] <> Path.extname(db_sound.filename),
      source_type: params["source_type"] || db_sound.source_type,
      url: params["url"],
      user_id: db_sound.user_id || user_id,
      volume:
        Volume.percent_to_decimal(params["volume"], Volume.decimal_to_percent(db_sound.volume)),
      color: params["color"],
      image_filename: resolve_image_filename(params, db_sound)
    }
  end

  defp resolve_image_filename(%{"image_filename" => f}, _db_sound) when is_binary(f) and f != "",
    do: f

  defp resolve_image_filename(%{"clear_image" => v}, _db_sound)
       when v not in [nil, false, "false", ""], do: nil

  defp resolve_image_filename(_params, db_sound), do: db_sound.image_filename

  defp maybe_delete_old_image(%{"image_filename" => new, "clear_image" => _}, db_sound)
       when is_binary(new) and new != "" do
    if new != db_sound.image_filename, do: ImageProcessing.delete_image(db_sound.image_filename)
  end

  defp maybe_delete_old_image(%{"image_filename" => new}, db_sound)
       when is_binary(new) and new != "" do
    if new != db_sound.image_filename, do: ImageProcessing.delete_image(db_sound.image_filename)
  end

  defp maybe_delete_old_image(%{"clear_image" => v}, db_sound)
       when v not in [nil, false, "false", ""] do
    ImageProcessing.delete_image(db_sound.image_filename)
  end

  defp maybe_delete_old_image(_params, _db_sound), do: :ok

  defp maybe_remove_local_file(%{source_type: "local", storage_key: key}) when is_binary(key) do
    _ = File.rm(UploadsPath.file_path(key))
    :ok
  end

  defp maybe_remove_local_file(_), do: :ok

  defp update_user_settings(sound, user_id, updated_sound, params) do
    user_setting =
      Enum.find(sound.user_sound_settings, &(&1.user_id == user_id)) ||
        %Soundboard.UserSoundSetting{sound_id: sound.id, user_id: user_id}

    setting_params = %{
      user_id: user_id,
      sound_id: sound.id,
      is_join_sound: params["is_join_sound"] == "true",
      is_leave_sound: params["is_leave_sound"] == "true"
    }

    Soundboard.UserSoundSetting.clear_conflicting_settings(
      user_id,
      sound.id,
      setting_params.is_join_sound,
      setting_params.is_leave_sound
    )

    case user_setting
         |> Soundboard.UserSoundSetting.changeset(setting_params)
         |> Repo.insert_or_update() do
      {:ok, _setting} ->
        updated_sound

      {:error, changeset} ->
        Logger.error("Failed to update user settings: #{inspect(changeset)}")
        Repo.rollback(changeset)
    end
  end
end
