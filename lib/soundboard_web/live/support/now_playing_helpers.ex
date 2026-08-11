defmodule SoundboardWeb.Live.Support.NowPlayingHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Soundboard.AudioPlayer
  alias Soundboard.Sounds
  alias SoundboardWeb.SoundHelpers

  def assign_defaults(socket) do
    socket
    |> assign(:now_playing, nil)
    |> restore_from_player()
  end

  def restore_from_player(socket) do
    case AudioPlayer.now_playing() do
      nil -> socket
      payload when is_map(payload) -> assign_from_event(socket, payload)
      _ -> socket
    end
  end

  def assign_from_event(socket, %{filename: "All sounds stopped"}) do
    clear(socket)
  end

  def assign_from_event(socket, %{filename: filename, played_by: played_by} = event)
      when is_binary(filename) do
    sound_id = event_value(event, :sound_id, fetch_sound_id(filename))
    duration_ms = event_value(event, :duration_ms, nil)
    started_at = event_value(event, :started_at, System.system_time(:millisecond))
    live? = event_value(event, :live?, false)
    media_type = event_value(event, :media_type, "sound")
    thumbnail_url = event_value(event, :thumbnail_url, nil)
    navigate_to = event_value(event, :navigate_to, nil)

    assign(socket, :now_playing, %{
      filename: filename,
      display_name: display_name(filename),
      played_by: played_by,
      sound_id: normalize_sound_id(sound_id),
      duration_ms: normalize_duration(duration_ms),
      started_at: normalize_started_at(started_at),
      live?: live? == true,
      media_type: media_type,
      thumbnail_url: thumbnail_url,
      navigate_to: navigate_to
    })
  end

  def assign_from_event(socket, _), do: socket

  def clear(socket), do: assign(socket, :now_playing, nil)

  defp event_value(event, key, default) do
    case Map.fetch(event, key) do
      {:ok, nil} -> Map.get(event, Atom.to_string(key), default)
      {:ok, value} -> value
      :error -> Map.get(event, Atom.to_string(key), default)
    end
  end

  # Sound files use basename/rootname; video titles (incl. those with "/") show as-is.
  defp display_name(name) do
    if String.match?(name, ~r/\.(mp3|mp4|wav|ogg|m4a|webm)$/i) do
      SoundHelpers.display_name(name)
    else
      name
    end
  end

  defp fetch_sound_id(filename) do
    case Sounds.fetch_sound_id(filename) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp normalize_sound_id(id) when is_integer(id), do: id

  defp normalize_sound_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp normalize_sound_id(_), do: nil

  defp normalize_duration(ms) when is_integer(ms) and ms > 0, do: ms

  defp normalize_duration(ms) when is_binary(ms) do
    case Integer.parse(ms) do
      {int, _} when int > 0 -> int
      _ -> nil
    end
  end

  defp normalize_duration(_), do: nil

  defp normalize_started_at(ms) when is_integer(ms) and ms > 0, do: ms

  defp normalize_started_at(ms) when is_binary(ms) do
    case Integer.parse(ms) do
      {int, _} when int > 0 -> int
      _ -> System.system_time(:millisecond)
    end
  end

  defp normalize_started_at(_), do: System.system_time(:millisecond)
end
