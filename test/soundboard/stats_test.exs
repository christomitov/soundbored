defmodule Soundboard.StatsTest do
  @moduledoc """
  Test for the Stats module.
  """
  use Soundboard.DataCase
  alias Soundboard.{Accounts.User, PubSubTopics, Sound, Stats, Stats.Play}

  describe "stats" do
    setup do
      user = insert_user()
      sound = insert_sound(user)
      %{user: user, sound: sound}
    end

    test "track_play creates a play record", %{user: user, sound: sound} do
      assert {:ok, play} = Stats.track_play(sound.filename, user.id)
      assert play.played_filename == sound.filename
      assert play.sound_id == sound.id
      assert play.user_id == user.id
    end

    test "get_top_sounds preserves the played filename snapshot after a sound is renamed", %{
      user: user,
      sound: sound
    } do
      today = Date.utc_today()
      original_filename = sound.filename
      Stats.track_play(original_filename, user.id)

      {:ok, _renamed_sound} =
        sound
        |> Sound.changeset(%{filename: "renamed_#{System.unique_integer()}.mp3"})
        |> Repo.update()

      results = Stats.get_top_sounds(today, today)

      sound_plays =
        Enum.find(results, fn {filename, _count} -> filename == original_filename end)

      assert sound_plays != nil
      assert {^original_filename, count} = sound_plays
      assert count >= 1
    end

    test "get_recent_plays falls back to the stored sound name when a sound is deleted", %{
      user: user,
      sound: sound
    } do
      Stats.track_play(sound.filename, user.id)
      Repo.delete!(sound)

      assert [{_id, filename, username, _timestamp}] = Stats.get_recent_plays(limit: 1)
      assert filename == sound.filename
      assert username == user.username
    end

    test "play changeset requires sound_id" do
      changeset = Play.changeset(%Play{}, %{played_filename: "beep.mp3", user_id: 123})

      assert %{sound_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "get_top_users returns users ordered by play count", %{user: user, sound: sound} do
      today = Date.utc_today()
      Enum.each(1..3, fn _ -> Stats.track_play(sound.filename, user.id) end)

      results = Stats.get_top_users(today, today)
      user_plays = Enum.find(results, fn {username, _count} -> username == user.username end)

      assert user_plays != nil
      assert {_username, count} = user_plays
      assert count >= 3
    end

    test "get_top_sounds returns sounds ordered by play count", %{user: user, sound: sound} do
      today = Date.utc_today()
      Enum.each(1..3, fn _ -> Stats.track_play(sound.filename, user.id) end)

      results = Stats.get_top_sounds(today, today)
      sound_plays = Enum.find(results, fn {filename, _count} -> filename == sound.filename end)

      assert sound_plays != nil
      assert {_filename, count} = sound_plays
      assert count >= 3
    end

    test "get_recent_plays returns most recent plays", %{user: user, sound: sound} do
      Stats.track_play(sound.filename, user.id)

      assert [{_id, filename, username, _timestamp}] = Stats.get_recent_plays(limit: 1)
      assert filename == sound.filename
      assert username == user.username
    end

    test "reset_weekly_stats deletes old plays", %{user: user, sound: sound} do
      old_date =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-8, :day)
        |> NaiveDateTime.truncate(:second)

      play = %Play{
        played_filename: sound.filename,
        sound_id: sound.id,
        user_id: user.id,
        inserted_at: old_date
      }

      Repo.insert!(play)

      Stats.track_play(sound.filename, user.id)

      initial_count = length(Repo.all(Play))
      Stats.reset_weekly_stats()
      final_count = length(Repo.all(Play))

      # Should have at least one less play after reset
      assert final_count < initial_count
    end

    test "track_play broadcasts stats only after a successful insert", %{sound: sound} do
      PubSubTopics.subscribe_stats()

      assert {:error, changeset} = Stats.track_play(sound.filename, nil)
      assert "can't be blank" in errors_on(changeset).user_id
      refute_receive {:stats_updated}

      assert {:ok, _play} = Stats.track_play(sound.filename, sound.user_id)
      assert_receive {:stats_updated}
      refute_receive {:stats_updated}
    end

    test "broadcast_stats_update sends update message" do
      PubSubTopics.subscribe_stats()

      Stats.broadcast_stats_update()

      assert_receive {:stats_updated}
      refute_receive {:stats_updated}
    end
  end

  # Helper functions
  defp insert_sound(user) do
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test_sound#{System.unique_integer()}.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert()

    sound
  end

  defp insert_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer()}",
        discord_id: "123456789",
        avatar: "test_avatar.jpg"
      })
      |> Repo.insert()

    user
  end
end
