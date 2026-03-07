defmodule Soundboard.Discord.VoiceTest do
  use ExUnit.Case, async: true

  import Mock

  alias Soundboard.Discord.Voice

  test "uses the supported EDA.Voice.play arity" do
    if function_exported?(EDA.Voice, :play, 4) do
      with_mock EDA.Voice,
        play: fn "123", "file.mp3", :url, [volume: 1.2] -> :ok end do
        assert :ok = Voice.play(123, "file.mp3", :url, volume: 1.2)

        assert_called(EDA.Voice.play("123", "file.mp3", :url, volume: 1.2))
      end
    else
      with_mock EDA.Voice,
        play: fn "123", "file.mp3", :url -> :ok end do
        assert :ok = Voice.play(123, "file.mp3", :url, volume: 1.2)

        assert_called(EDA.Voice.play("123", "file.mp3", :url))
      end
    end
  end
end
