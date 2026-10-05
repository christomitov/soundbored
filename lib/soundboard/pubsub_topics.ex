defmodule Soundboard.PubSubTopics do
  @moduledoc false

  alias Phoenix.PubSub

  @files_topic "soundboard.files"
  @playback_topic "soundboard.playback"
  @stats_topic "soundboard.stats"

  def files_topic, do: @files_topic
  def stats_topic, do: @stats_topic

  @doc """
  Playback topic for a guild: `"soundboard.playback:{guild_id}"`.
  """
  def playback_topic(guild_id \\ nil),
    do: "#{@playback_topic}:#{Soundboard.Tenants.scope_guild_id(guild_id)}"

  def subscribe_files, do: PubSub.subscribe(Soundboard.PubSub, @files_topic)

  def subscribe_playback(guild_id \\ nil),
    do: PubSub.subscribe(Soundboard.PubSub, playback_topic(guild_id))

  def subscribe_stats, do: PubSub.subscribe(Soundboard.PubSub, @stats_topic)

  def broadcast_files_updated do
    PubSub.broadcast(Soundboard.PubSub, @files_topic, {:files_updated})
  end

  def broadcast_stats_updated do
    PubSub.broadcast(Soundboard.PubSub, @stats_topic, {:stats_updated})
  end

  def broadcast_sound_played(sound_name, username, guild_id \\ nil) do
    PubSub.broadcast(
      Soundboard.PubSub,
      playback_topic(guild_id),
      {:sound_played, %{filename: sound_name, played_by: username}}
    )
  end

  def broadcast_error(message, guild_id \\ nil) do
    PubSub.broadcast(Soundboard.PubSub, playback_topic(guild_id), {:error, message})
  end
end
