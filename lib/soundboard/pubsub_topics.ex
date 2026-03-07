defmodule Soundboard.PubSubTopics do
  @moduledoc false

  alias Phoenix.PubSub

  @files_topic "soundboard.files"
  @playback_topic "soundboard.playback"
  @stats_topic "soundboard.stats"

  def files_topic, do: @files_topic
  def playback_topic, do: @playback_topic
  def stats_topic, do: @stats_topic

  def subscribe_files, do: PubSub.subscribe(Soundboard.PubSub, @files_topic)
  def subscribe_playback, do: PubSub.subscribe(Soundboard.PubSub, @playback_topic)
  def subscribe_stats, do: PubSub.subscribe(Soundboard.PubSub, @stats_topic)

  def broadcast_files_updated do
    PubSub.broadcast(Soundboard.PubSub, @files_topic, {:files_updated})
  end

  def broadcast_stats_updated do
    PubSub.broadcast(Soundboard.PubSub, @stats_topic, {:stats_updated})
  end

  def broadcast_sound_played(sound_name, username) do
    PubSub.broadcast(
      Soundboard.PubSub,
      @playback_topic,
      {:sound_played, %{filename: sound_name, played_by: username}}
    )
  end

  def broadcast_error(message) do
    PubSub.broadcast(Soundboard.PubSub, @playback_topic, {:error, message})
  end
end
