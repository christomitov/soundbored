defmodule Soundboard.AudioPlayer.Notifier do
  @moduledoc false

  alias Soundboard.PubSubTopics

  def sound_played(sound_name, actor_name) do
    PubSubTopics.broadcast_sound_played(sound_name, actor_name)
  end

  def error(message) do
    PubSubTopics.broadcast_error(message)
  end
end
