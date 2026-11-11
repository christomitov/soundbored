defmodule Soundboard.AudioPlayer.SoundLibrary do
  @moduledoc false

  require Logger

  alias Soundboard.Sound
  alias Soundboard.Tenants

  @cache_table :sound_meta_cache

  def ensure_cache do
    case :ets.info(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:set, :named_table, :public, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Resolves a sound to `{input, volume}` for playback, scoped to `guild_id`.
  Cache keys are `{guild_id, sound_name}` so tenants cannot read each other's
  sounds by name.
  """
  def get_sound_path(guild_id, sound_name) do
    guild_id = Tenants.scope_guild_id(guild_id)
    ensure_cache()

    case lookup_cached_sound(guild_id, sound_name) do
      {:hit, {_type, input, volume}} -> {:ok, {input, volume}}
      :miss -> resolve_and_cache_sound(guild_id, sound_name)
    end
  end

  @doc """
  Removes any cached metadata for the given `{guild_id, sound_name}` so future
  plays use fresh data.
  """
  def invalidate_cache(guild_id, sound_name) when is_binary(sound_name) do
    ensure_cache()
    :ets.delete(@cache_table, {Tenants.scope_guild_id(guild_id), sound_name})
    :ok
  end

  defp lookup_cached_sound(guild_id, sound_name) do
    case :ets.lookup(@cache_table, {guild_id, sound_name}) do
      [{{^guild_id, ^sound_name}, %{source_type: source, input: input, volume: volume}}] ->
        {:hit, {source, input, volume}}

      _ ->
        :miss
    end
  end

  defp resolve_and_cache_sound(guild_id, sound_name) do
    case Soundboard.Repo.get_by(Sound, filename: sound_name, guild_id: guild_id) do
      nil ->
        Logger.error("Sound not found in database: #{sound_name} (guild #{guild_id})")
        {:error, "Sound not found"}

      %{source_type: "url", url: url, volume: volume} when is_binary(url) ->
        meta = %{source_type: "url", input: url, volume: volume || 1.0}
        cache_sound(guild_id, sound_name, meta)
        {:ok, {meta.input, meta.volume}}

      %{source_type: "local", storage_key: key, volume: volume} when is_binary(key) ->
        path = resolve_upload_path(key)

        if File.exists?(path) do
          meta = %{source_type: "local", input: path, volume: volume || 1.0}
          cache_sound(guild_id, sound_name, meta)
          {:ok, {meta.input, meta.volume}}
        else
          Logger.error("Local file not found: #{path}")
          {:error, "Sound file not found at #{path}"}
        end

      _sound ->
        Logger.error("Invalid sound configuration for #{sound_name}")
        {:error, "Invalid sound configuration"}
    end
  end

  defp resolve_upload_path(filename) do
    Soundboard.UploadsPath.file_path(filename)
  end

  defp cache_sound(guild_id, sound_name, meta) do
    :ets.insert(@cache_table, {{guild_id, sound_name}, meta})
  end
end
