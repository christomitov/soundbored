defmodule Soundboard.AudioPlayer.Notifier do
  @moduledoc false

  alias Phoenix.PubSub
  alias Soundboard.AudioPlayer
  alias Soundboard.PubSubTopics

  def sound_played(sound_name, actor_name, meta \\ %{}) do
    payload = PubSubTopics.build_sound_played_payload(sound_name, actor_name, meta)
    AudioPlayer.set_now_playing(payload)
    PubSub.broadcast(Soundboard.PubSub, PubSubTopics.playback_topic(), {:sound_played, payload})
  end

  def playback_stopped do
    AudioPlayer.clear_now_playing()
    PubSubTopics.broadcast_playback_stopped()
  end

  def error(message) do
    PubSubTopics.broadcast_error(message)
  end
end
