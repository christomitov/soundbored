defmodule Soundboard.AudioPlayer.Notifier do
  @moduledoc false

  alias Soundboard.PubSubTopics

  def sound_played(sound_name, actor_name) do
    PubSubTopics.broadcast_sound_played(sound_name, actor_name)
  end

  def sound_played(sound_name, actor_name, meta) do
    PubSubTopics.broadcast_sound_played(sound_name, actor_name, meta)
  end

  def playback_stopped do
    PubSubTopics.broadcast_playback_stopped()
  end

  def error(message) do
    PubSubTopics.broadcast_error(message)
  end
end
