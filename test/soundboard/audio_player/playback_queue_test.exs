defmodule Soundboard.AudioPlayer.PlaybackQueueTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Soundboard.AudioPlayer.{PlaybackQueue, State}
  alias Soundboard.FakeVoice

  @channel "channel-9"

  setup do
    %{guild: "queue-#{System.unique_integer([:positive])}"}
  end

  test "cancelling an in-flight playback does not terminate its owner", %{guild: guild} do
    test_pid = self()
    FakeVoice.claim(guild, channel: @channel, play: [:hold])

    owner =
      spawn(fn ->
        state = PlaybackQueue.enqueue(state(guild), request(guild, "intro"), 35)
        send(test_pid, {:playback_owner_ready, self()})

        receive do
          :cancel ->
            PlaybackQueue.clear_all(state)
            send(test_pid, :playback_owner_survived)
            receive do: (:never -> :ok)
        end
      end)

    owner_ref = Process.monitor(owner)

    assert_receive {:fake_voice_holding, ^guild, task}
    task_ref = Process.monitor(task)
    assert_receive {:playback_owner_ready, ^owner}
    send(owner, :cancel)

    assert_receive :playback_owner_survived
    assert_receive {:DOWN, ^task_ref, :process, ^task, :killed}
    refute_receive {:DOWN, ^owner_ref, :process, ^owner, _reason}

    Process.exit(owner, :kill)
  end

  test "a failed or crashed playback makes way for the queued request", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel)

    for finish <- [
          &PlaybackQueue.handle_task_result(&1, :error),
          &PlaybackQueue.handle_task_down(&1, :boom)
        ] do
      state =
        finish.(
          state(guild,
            current_playback: request(guild, "old"),
            pending_request: request(guild, "next")
          )
        )

      assert_receive {:fake_voice, ^guild, {:play, "https://sounds.example/next.mp3", :url, _}}
      assert %{sound_name: "next.mp3"} = state.current_playback
      assert state.pending_request == nil
    end
  end

  test "a queued request for a channel the bot has left is dropped", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel)

    state =
      PlaybackQueue.handle_task_result(
        state(guild,
          voice_channel: {guild, "other-channel"},
          current_playback: request(guild, "old"),
          pending_request: request(guild, "next")
        ),
        :error
      )

    assert state.current_playback == nil
    assert state.pending_request == nil
    refute_receive {:fake_voice, ^guild, {:play, _, _, _}}, 50
  end

  test "the interrupt watchdog stops again while audio plays, then starts the queued request",
       %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel, playing: true, stop: :ignored)

    interrupting =
      state(guild,
        interrupting: true,
        interrupt_watchdog_attempt: 1,
        current_playback: request(guild, "old"),
        pending_request: request(guild, "next")
      )

    still_playing = PlaybackQueue.handle_interrupt_watchdog(interrupting, guild, 1, 20, 35)

    assert_receive {:fake_voice, ^guild, :stop}
    assert still_playing.current_playback.sound_name == "old.mp3"
    assert still_playing.pending_request.sound_name == "next.mp3"
    assert still_playing.interrupt_watchdog_attempt == 2
    assert_receive {:interrupt_watchdog, ^guild, 2}

    FakeVoice.claim(guild, channel: @channel, playing: false)

    stopped = PlaybackQueue.handle_interrupt_watchdog(still_playing, guild, 2, 20, 35)

    assert_receive {:fake_voice, ^guild, {:play, "https://sounds.example/next.mp3", :url, _}}
    assert %{sound_name: "next.mp3"} = stopped.current_playback
    assert stopped.interrupting == false
    assert stopped.interrupt_watchdog_attempt == 0
  end

  test "the interrupt watchdog forces the queued request after its last attempt",
       %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel, playing: true)

    state =
      PlaybackQueue.handle_interrupt_watchdog(
        state(guild,
          interrupting: true,
          interrupt_watchdog_attempt: 20,
          current_playback: request(guild, "old"),
          pending_request: request(guild, "next")
        ),
        guild,
        20,
        20,
        35
      )

    assert_receive {:fake_voice, ^guild, first_call}
    assert first_call == :stop
    assert_receive {:fake_voice, ^guild, {:play, "https://sounds.example/next.mp3", :url, _}}
    refute_receive {:fake_voice, ^guild, _}, 50
    assert %{sound_name: "next.mp3"} = state.current_playback
    assert state.interrupting == false
    assert state.interrupt_watchdog_attempt == 0
  end

  test "a stale interrupt watchdog message changes nothing", %{guild: guild} do
    FakeVoice.claim(guild, channel: @channel, playing: true)
    idle = state(guild, current_playback: request(guild, "old"))

    assert PlaybackQueue.handle_interrupt_watchdog(idle, guild, 1, 20, 35) == idle
    refute_received {:fake_voice, ^guild, _}
  end

  defp state(guild, overrides \\ []) do
    struct!(
      State,
      Keyword.merge(
        [
          guild_id: guild,
          voice_channel: {guild, @channel},
          current_playback: nil,
          pending_request: nil,
          interrupting: false,
          interrupt_watchdog_ref: nil,
          interrupt_watchdog_attempt: 0
        ],
        overrides
      )
    )
  end

  defp request(guild, name) do
    %{
      guild_id: guild,
      channel_id: @channel,
      sound_name: "#{name}.mp3",
      path_or_url: "https://sounds.example/#{name}.mp3",
      volume: 1.0,
      actor: "System"
    }
  end
end
