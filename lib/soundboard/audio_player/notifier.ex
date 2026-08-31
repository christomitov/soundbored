defmodule Soundboard.AudioPlayer.Notifier do
  @moduledoc false

  alias Soundboard.PubSubTopics

  def sound_played(sound_name, actor_name, guild_id \\ nil) do
    PubSubTopics.broadcast_sound_played(sound_name, actor_name, guild_id)
  end

  def error(message, guild_id \\ nil) do
    PubSubTopics.broadcast_error(message, guild_id)
  end
end
