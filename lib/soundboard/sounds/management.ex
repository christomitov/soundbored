defmodule Soundboard.Sounds.Management do
  @moduledoc """
  Domain-level sound update/delete operations used by LiveViews.

  Sound metadata edits are collaborative for signed-in users, while deletion
  remains restricted to the original uploader. Per-user join/leave preferences
  are stored separately so editors keep their own settings without taking over
  sound ownership.
  """

  alias Soundboard.{AudioPlayer, PubSubTopics, Repo, Sound, UploadsPath, Volume}
  require Logger

  def update_sound(%Sound{} = sound, user_id, params) do
    with {:ok, db_sound} <- fetch(sound),
         {:ok, updated_sound} <- update_in_transaction(db_sound, user_id, params) do
      PubSubTopics.broadcast_files_updated()
      {:ok, updated_sound}
    end
  end

  defp update_in_transaction(db_sound, user_id, params) do
    Repo.transaction(fn ->
      db_sound = Repo.preload(db_sound, :user_sound_settings)

      new_filename = params["filename"] <> Path.extname(db_sound.filename)

      sound_params = %{
        filename: new_filename,
        source_type: params["source_type"] || db_sound.source_type,
        url: params["url"],
        user_id: db_sound.user_id || user_id,
        volume:
          Volume.percent_to_decimal(params["volume"], Volume.decimal_to_percent(db_sound.volume))
      }

      case Repo.update(Sound.changeset(db_sound, sound_params)) do
        {:ok, updated_sound} ->
          updated_sound = update_user_settings(db_sound, user_id, updated_sound, params)
          AudioPlayer.invalidate_cache(db_sound.guild_id, db_sound.filename)
          AudioPlayer.invalidate_cache(updated_sound.guild_id, updated_sound.filename)
          updated_sound

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def delete_sound(%Sound{} = sound, user_id) do
    with {:ok, db_sound} <- fetch(sound),
         true <- db_sound.user_id == user_id,
         {:ok, _deleted_sound} <- Repo.delete(db_sound) do
      AudioPlayer.invalidate_cache(db_sound.guild_id, db_sound.filename)
      maybe_remove_local_file(db_sound)
      PubSubTopics.broadcast_files_updated()
      :ok
    else
      false -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch(%Sound{id: id}) do
    case Repo.get(Sound, id) do
      nil -> {:error, :not_found}
      db_sound -> {:ok, db_sound}
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
      guild_id: sound.guild_id,
      is_join_sound: params["is_join_sound"] == "true",
      is_leave_sound: params["is_leave_sound"] == "true"
    }

    Soundboard.UserSoundSetting.clear_conflicting_settings(
      user_id,
      sound.id,
      setting_params.is_join_sound,
      setting_params.is_leave_sound,
      sound.guild_id
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
