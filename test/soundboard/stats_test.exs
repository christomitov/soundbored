defmodule Soundboard.StatsTest do
  @moduledoc """
  Test for the Stats module.
  """
  use Soundboard.DataCase
  alias Soundboard.Accounts.Tenants
  alias Soundboard.{Accounts.User, Sound, Stats, Stats.Play}

  describe "stats" do
    setup do
      user = insert_user()
      sound = insert_sound(user)
      %{user: user, sound: sound}
    end

    test "track_play creates a play record", %{user: user, sound: sound} do
      assert {:ok, play} = Stats.track_play(sound.filename, user.id)
      assert play.sound_name == sound.filename
      assert play.user_id == user.id
      assert play.tenant_id == user.tenant_id
    end

    test "get_top_users returns users ordered by play count", %{user: user, sound: sound} do
      today = Date.utc_today()
      Enum.each(1..3, fn _ -> Stats.track_play(sound.filename, user.id) end)

      results = Stats.get_top_users(user.tenant_id, today, today)
      user_plays = Enum.find(results, fn {username, _count} -> username == user.username end)

      assert user_plays != nil
      assert {_username, count} = user_plays
      assert count >= 3
    end

    test "get_top_sounds returns sounds ordered by play count", %{user: user, sound: sound} do
      today = Date.utc_today()
      Enum.each(1..3, fn _ -> Stats.track_play(sound.filename, user.id) end)

      results = Stats.get_top_sounds(user.tenant_id, today, today)
      sound_plays = Enum.find(results, fn {filename, _count} -> filename == sound.filename end)

      assert sound_plays != nil
      assert {_filename, count} = sound_plays
      assert count >= 3
    end

    test "get_recent_plays returns most recent plays", %{user: user, sound: sound} do
      Stats.track_play(sound.filename, user.id)

      assert [{_id, filename, username, _timestamp}] =
               Stats.get_recent_plays(user.tenant_id, limit: 1)

      assert filename == sound.filename
      assert username == user.username
    end

    test "reset_weekly_stats deletes old plays", %{user: user, sound: sound} do
      # Create an old play with truncated timestamp
      old_date =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-8, :day)
        |> NaiveDateTime.truncate(:second)

      play = %Play{
        sound_name: sound.filename,
        user_id: user.id,
        tenant_id: user.tenant_id,
        inserted_at: old_date
      }

      Repo.insert!(play)

      # Create a recent play
      Stats.track_play(sound.filename, user.id)

      initial_count = length(Repo.all(Play))
      Stats.reset_weekly_stats(user.tenant_id)
      final_count = length(Repo.all(Play))

      # Should have at least one less play after reset
      assert final_count < initial_count
    end

    test "broadcast_stats_update sends update message", %{user: user} do
      tenant_id = user.tenant_id
      stats_topic = Stats.stats_topic(tenant_id)
      Phoenix.PubSub.subscribe(Soundboard.PubSub, stats_topic)

      Stats.broadcast_stats_update(tenant_id)

      assert_receive {:stats_updated, ^tenant_id}
      refute_receive {:stats_updated, ^tenant_id}
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
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer()}",
        discord_id: "123456789",
        avatar: "test_avatar.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    user
  end
end
