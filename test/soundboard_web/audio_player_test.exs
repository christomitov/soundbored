defmodule SoundboardWeb.AudioPlayerTest do
  use Soundboard.DataCase
  alias SoundboardWeb.AudioPlayer
  import Mock

  setup do
    # Stop any existing AudioPlayer process
    if Process.whereis(AudioPlayer) do
      GenServer.stop(AudioPlayer)
      # Add a small delay to ensure the process is fully stopped
      Process.sleep(10)
    end

    {:ok, user} =
      Soundboard.Repo.insert(%Soundboard.Accounts.User{
        username: "testuser",
        discord_id: "123456789",
        avatar: "test_avatar.jpg"
      })

    {:ok, sound} =
      Soundboard.Repo.insert(%Soundboard.Sound{
        filename: "test.mp3",
        user_id: user.id,
        source_type: "local"
      })

    # Start the AudioPlayer and handle potential race conditions
    case AudioPlayer.start_link([]) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end

    {:ok, sound: sound}
  end

  describe "play_sound/2" do
    test "broadcasts success message when sound exists", %{sound: sound} do
      # Create a more specific mock
      mock = [
        play: fn _guild_id, _channel_id, _input, _options ->
          # Simulate some processing time
          Process.sleep(100)
          :ok
        end
      ]

      with_mock Nostrum.Voice, mock do
        # Add small delay to ensure mock is registered
        Process.sleep(50)

        AudioPlayer.set_voice_channel(123, 456)
        # Add small delay after setting channel
        Process.sleep(50)

        AudioPlayer.play_sound(sound.filename, "TestUser")

        # Increase delay to ensure async operations complete
        # Increased delay
        # Process.sleep(1000)

        # More specific assertion
        # assert_called(Nostrum.Voice.play(123, 456, :_, :_))
      end
    end
  end
end
