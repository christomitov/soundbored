defmodule Soundboard.Discord.VoiceTest do
  use ExUnit.Case, async: true

  alias Soundboard.Discord.Voice
  alias Soundboard.FakeVoice

  setup do
    guild_id = System.unique_integer([:positive])
    %{guild_id: guild_id, guild: Integer.to_string(guild_id)}
  end

  test "play passes the volume to EDA with the guild id as a string", %{
    guild_id: id,
    guild: guild
  } do
    FakeVoice.claim(guild, channel: "voice-1")

    assert :ok = Voice.play(id, "file.mp3", :url, volume: 1.2)

    assert_received {:fake_voice, ^guild, {:play, "file.mp3", :url, [volume: 1.2]}}
  end
end
