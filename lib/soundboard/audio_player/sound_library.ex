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
  def get_sound_path(sound_name) when is_binary(sound_name),
    do: get_sound_path(Tenants.default_guild_id(), sound_name)

  def get_sound_path(guild_id, sound_name) do
    guild_id = Tenants.scope_guild_id(guild_id)
    ensure_cache()

    case lookup_cached_sound(guild_id, sound_name) do
      {:hit, {_type, input, volume}} -> {:ok, {input, volume}}
      :miss -> resolve_and_cache_sound(guild_id, sound_name)
    end
  end

  def prepare_play_input(sound_name, path_or_url) when is_binary(sound_name),
    do: prepare_play_input(Tenants.default_guild_id(), sound_name, path_or_url)

  def prepare_play_input(guild_id, sound_name, path_or_url) do
    guild_id = Tenants.scope_guild_id(guild_id)
    ensure_cache()

    case :ets.lookup(@cache_table, {guild_id, sound_name}) do
      [{{^guild_id, ^sound_name}, %{source_type: source_type}}]
      when source_type in ["url", "local"] ->
        {path_or_url, :url}

      _ ->
        case Soundboard.Repo.get_by(Sound, filename: sound_name, guild_id: guild_id) do
          %{source_type: source_type} when source_type in ["url", "local"] ->
            {path_or_url, :url}

          _ ->
            Logger.warning("Unknown source type for #{sound_name}; defaulting to direct playback")
            {path_or_url, :url}
        end
    end
  end

  @doc """
  Removes any cached metadata for the given `{guild_id, sound_name}` so future
  plays use fresh data. The 1-arity form targets the default guild (compat).
  """
  def invalidate_cache(guild_id, sound_name) when is_binary(sound_name) do
    ensure_cache()
    :ets.delete(@cache_table, {Tenants.scope_guild_id(guild_id), sound_name})
    :ok
  end

  def invalidate_cache(sound_name) when is_binary(sound_name) do
    invalidate_cache(Tenants.default_guild_id(), sound_name)
  end

  def invalidate_cache(_), do: :ok

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
