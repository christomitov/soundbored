defmodule Soundboard.Sounds.Uploads.Creator do
  @moduledoc false

  alias Soundboard.{PubSubTopics, Repo, Sound, Stats, UserSoundSetting}
  alias Soundboard.Sounds.Tags
  alias Soundboard.Sounds.Uploads.Source

  @spec create(map(), map()) :: {:ok, Sound.t()} | {:error, term()}
  def create(params, source) do
    Repo.transaction(fn ->
      with {:ok, tags} <- Tags.resolve_many(params.tags),
           {:ok, sound} <- insert_sound(params, source, tags),
           {:ok, _setting} <- insert_user_setting(sound, params),
           sound <- Repo.preload(sound, [:tags, :user, :user_sound_settings]) do
        sound
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, sound} ->
        broadcast_updates()
        {:ok, sound}

      {:error, reason} ->
        Source.cleanup_local_file(source.copied_file_path)
        {:error, reason}
    end
  end

  defp insert_sound(params, source, tags) do
    sound_attrs = %{
      filename: source.filename,
      source_type: source.source_type,
      url: source.url,
      user_id: params.user.id,
      volume: params.volume,
      tags: tags
    }

    %Sound{}
    |> Sound.changeset(sound_attrs)
    |> Repo.insert()
  end

  defp insert_user_setting(sound, params) do
    attrs = %{
      user_id: params.user.id,
      sound_id: sound.id,
      is_join_sound: params.is_join_sound,
      is_leave_sound: params.is_leave_sound
    }

    UserSoundSetting.clear_conflicting_settings(
      params.user.id,
      sound.id,
      params.is_join_sound,
      params.is_leave_sound
    )

    %UserSoundSetting{}
    |> UserSoundSetting.changeset(attrs)
    |> Repo.insert()
  end

  defp broadcast_updates do
    PubSubTopics.broadcast_files_updated()
    Stats.broadcast_stats_update()
  end
end
