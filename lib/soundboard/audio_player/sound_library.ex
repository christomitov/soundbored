defmodule Soundboard.AudioPlayer.SoundLibrary do
  @moduledoc false

  require Logger

  alias Soundboard.Sound

  def ensure_cache do
    case :ets.info(:sound_meta_cache) do
      :undefined ->
        :ets.new(:sound_meta_cache, [:set, :named_table, :public, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  def get_sound_path(sound_name) do
    Logger.info("Getting sound path for: #{sound_name}")
    ensure_cache()

    case lookup_cached_sound(sound_name) do
      {:hit, {_type, input, volume}} -> {:ok, {input, volume}}
      :miss -> resolve_and_cache_sound(sound_name)
    end
  end

  def prepare_play_input(sound_name, path_or_url) do
    ensure_cache()

    case :ets.lookup(:sound_meta_cache, sound_name) do
      [{^sound_name, %{source_type: "url"}}] ->
        Logger.info("Using URL directly for remote sound (cached)")
        {path_or_url, :url}

      [{^sound_name, %{source_type: "local"}}] ->
        Logger.info("Using raw path for local file with :url type (cached)")
        {path_or_url, :url}

      _ ->
        sound = Soundboard.Repo.get_by(Sound, filename: sound_name)
        Logger.info("Playing sound (uncached): #{inspect(sound)}")
        Logger.info("Original path/URL: #{path_or_url}")

        case sound do
          %{source_type: "url"} ->
            Logger.info("Using URL directly for remote sound")
            {path_or_url, :url}

          %{source_type: "local"} ->
            Logger.info("Using raw path for local file with :url type")
            {path_or_url, :url}

          _ ->
            Logger.warning("Unknown source type, defaulting to raw path with :url type")
            {path_or_url, :url}
        end
    end
  end

  @doc """
  Removes any cached metadata for the given `sound_name` so future plays use fresh data.
  """
  def invalidate_cache(sound_name) when is_binary(sound_name) do
    ensure_cache()
    :ets.delete(:sound_meta_cache, sound_name)
    :ok
  end

  def invalidate_cache(_), do: :ok

  defp lookup_cached_sound(sound_name) do
    case :ets.lookup(:sound_meta_cache, sound_name) do
      [{^sound_name, %{source_type: source, input: input, volume: volume}}] ->
        Logger.info(
          "Found sound in cache: #{inspect(%{source_type: source, input: input, volume: volume})}"
        )

        {:hit, {source, input, volume}}

      _ ->
        :miss
    end
  end

  defp resolve_and_cache_sound(sound_name) do
    case Soundboard.Repo.get_by(Sound, filename: sound_name) do
      nil ->
        Logger.error("Sound not found in database: #{sound_name}")
        {:error, "Sound not found"}

      %{source_type: "url", url: url, volume: volume} when is_binary(url) ->
        Logger.info("Found URL sound: #{url}")
        meta = %{source_type: "url", input: url, volume: volume || 1.0}
        cache_sound(sound_name, meta)
        {:ok, {meta.input, meta.volume}}

      %{source_type: "local", filename: filename, volume: volume} when is_binary(filename) ->
        path = resolve_upload_path(filename)
        Logger.info("Resolved local file path: #{path}")

        if File.exists?(path) do
          meta = %{source_type: "local", input: path, volume: volume || 1.0}
          cache_sound(sound_name, meta)
          {:ok, {meta.input, meta.volume}}
        else
          Logger.error("Local file not found: #{path}")
          {:error, "Sound file not found at #{path}"}
        end

      sound ->
        Logger.error("Invalid sound configuration: #{inspect(sound)}")
        {:error, "Invalid sound configuration"}
    end
  end

  defp resolve_upload_path(filename) do
    Soundboard.UploadsPath.file_path(filename)
  end

  defp cache_sound(sound_name, meta) do
    :ets.insert(:sound_meta_cache, {sound_name, meta})
  end
end
