defmodule Soundboard.Sounds.Management do
  @moduledoc """
  Domain-level sound update/delete operations used by LiveViews.
  """

  alias Soundboard.{Repo, Sound, UploadsPath, Volume}
  require Logger

  def update_sound(%Sound{} = sound, user_id, params) do
    Repo.transaction(fn ->
      db_sound =
        Repo.get!(Sound, sound.id)
        |> Repo.preload(:user_sound_settings)

      old_path = UploadsPath.file_path(db_sound.filename)
      new_filename = params["filename"] <> Path.extname(db_sound.filename)
      new_path = UploadsPath.file_path(new_filename)

      sound_params = %{
        filename: new_filename,
        source_type: params["source_type"] || db_sound.source_type,
        url: params["url"],
        user_id: db_sound.user_id || user_id,
        volume:
          params["volume"]
          |> Volume.percent_to_decimal(Volume.decimal_to_percent(db_sound.volume))
      }

      updated_sound =
        case Sound.changeset(db_sound, sound_params) |> Repo.update() do
          {:ok, updated_sound} ->
            updated_sound = update_user_settings(db_sound, user_id, updated_sound, params)
            SoundboardWeb.AudioPlayer.invalidate_cache(db_sound.filename)
            SoundboardWeb.AudioPlayer.invalidate_cache(updated_sound.filename)
            updated_sound

          {:error, changeset} ->
            Repo.rollback(changeset)
        end

      case maybe_rename_local_file(db_sound, old_path, new_path) do
        :ok -> updated_sound
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  def delete_sound(%Sound{} = sound, user_id) do
    db_sound = Repo.get!(Sound, sound.id)

    if db_sound.user_id == user_id do
      case Repo.delete(db_sound) do
        {:ok, _deleted_sound} ->
          SoundboardWeb.AudioPlayer.invalidate_cache(db_sound.filename)

          if db_sound.source_type == "local" do
            _ = File.rm(UploadsPath.file_path(db_sound.filename))
          end

          :ok

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :forbidden}
    end
  end

  defp maybe_rename_local_file(%{source_type: "local"} = sound, old_path, new_path) do
    cond do
      sound.filename == Path.basename(new_path) ->
        :ok

      old_path == new_path ->
        :ok

      not File.exists?(old_path) ->
        Logger.error("Source file not found: #{old_path}")
        {:error, "Source file not found"}

      true ->
        case File.rename(old_path, new_path) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("File rename failed: #{inspect(reason)}")
            {:error, "Failed to rename file: #{inspect(reason)}"}
        end
    end
  end

  defp maybe_rename_local_file(_, _, _), do: :ok

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
