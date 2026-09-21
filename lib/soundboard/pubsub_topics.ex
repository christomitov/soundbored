defmodule Soundboard.PubSubTopics do
  @moduledoc false

  alias Phoenix.PubSub

  @files_topic "soundboard.files"
  @playback_topic "soundboard.playback"
  @stats_topic "soundboard.stats"
  @video_topic "soundboard.video"

  def files_topic, do: @files_topic
  def playback_topic, do: @playback_topic
  def stats_topic, do: @stats_topic
  def video_topic, do: @video_topic

  def subscribe_files, do: subscribe(@files_topic)
  def subscribe_playback, do: subscribe(@playback_topic)
  def subscribe_stats, do: subscribe(@stats_topic)
  def subscribe_video, do: subscribe(@video_topic)

  def broadcast_files_updated do
    PubSub.broadcast(Soundboard.PubSub, @files_topic, {:files_updated})
  end

  def broadcast_stats_updated do
    PubSub.broadcast(Soundboard.PubSub, @stats_topic, {:stats_updated})
  end

  def build_sound_played_payload(sound_name, username, meta \\ %{}) do
    meta
    |> Map.take([
      :sound_id,
      :duration_ms,
      :started_at,
      :live?,
      :media_type,
      :thumbnail_url,
      :navigate_to
    ])
    |> Map.merge(%{
      filename: sound_name,
      played_by: username,
      started_at: Map.get(meta, :started_at) || System.system_time(:millisecond)
    })
  end

  def broadcast_sound_played(sound_name, username, meta \\ %{}) do
    payload = build_sound_played_payload(sound_name, username, meta)
    PubSub.broadcast(Soundboard.PubSub, @playback_topic, {:sound_played, payload})
  end

  def broadcast_playback_stopped do
    PubSub.broadcast(Soundboard.PubSub, @playback_topic, {:playback_stopped})
  end

  def broadcast_error(message) do
    PubSub.broadcast(Soundboard.PubSub, @playback_topic, {:error, message})
  end

  def broadcast_video_state(session) do
    PubSub.broadcast(Soundboard.PubSub, @video_topic, {:video_state, session})
  end

  def broadcast_video_sync(sync) do
    PubSub.broadcast(Soundboard.PubSub, @video_topic, {:video_sync, sync})
  end

  def broadcast_video_error(message) do
    PubSub.broadcast(Soundboard.PubSub, @video_topic, {:video_error, message})
  end

  def broadcast_video_stopped do
    PubSub.broadcast(Soundboard.PubSub, @video_topic, {:video_stopped})
  end

  def broadcast_video_queue(queue) when is_list(queue) do
    PubSub.broadcast(Soundboard.PubSub, @video_topic, {:video_queue, queue})
  end

  defp subscribe(topic), do: PubSub.subscribe(Soundboard.PubSub, topic)
end
