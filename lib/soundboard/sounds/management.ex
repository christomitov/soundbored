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
    transaction_result =
      Repo.transaction(fn ->
        db_sound = Repo.get!(Sound, sound.id) |> Repo.preload(:user_sound_settings)
        sound_params = build_sound_params(db_sound, user_id, params)
        apply_sound_update(db_sound, user_id, sound_params, params)
      end)

    case transaction_result do
      {:ok, {updated_sound, db_sound}} ->
        maybe_cleanup_old_image(db_sound, params)
        {:ok, updated_sound}

      error ->
        error
    end
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
        params["volume"]
        |> Volume.percent_to_decimal(Volume.decimal_to_percent(db_sound.volume)),
      color: if(params["use_custom_color"] == "true", do: params["color"]),
      image_filename: resolve_image_filename(db_sound, params)
    }
  end

  defp resolve_image_filename(db_sound, params) do
    cond do
      params["image_filename"] -> params["image_filename"]
      params["clear_image"] -> nil
      true -> db_sound.image_filename
    end
  end

  defp apply_sound_update(db_sound, user_id, sound_params, params) do
    case Sound.changeset(db_sound, sound_params) |> Repo.update() do
      {:ok, updated_sound} ->
        updated_sound = update_user_settings(db_sound, user_id, updated_sound, params)
        AudioPlayer.invalidate_cache(db_sound.filename)
        AudioPlayer.invalidate_cache(updated_sound.filename)
        updated_sound

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp maybe_cleanup_old_image(db_sound, params) do
    if (params["image_filename"] && params["image_filename"] != db_sound.image_filename) ||
         params["clear_image"] do
      ImageProcessing.delete_image(db_sound.image_filename)
    end
  end

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
