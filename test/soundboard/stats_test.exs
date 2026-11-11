defmodule Soundboard.StatsTest do
  use Soundboard.DataCase, async: false

  alias Soundboard.{Accounts.User, PubSubTopics, Sound, Stats, Stats.Play}

  setup do
    user = insert_user("alice")
    %{user: user, sound: insert_sound(user, "beep.mp3")}
  end

  test "track_play records and broadcasts only real plays", %{user: user, sound: sound} do
    PubSubTopics.subscribe_stats()

    assert {:error, changeset} = Stats.track_play("missing.mp3", user.id)
    assert "can't be blank" in errors_on(changeset).sound_id
    assert {:error, changeset} = Stats.track_play(sound.filename, nil)
    assert "can't be blank" in errors_on(changeset).user_id
    assert Repo.aggregate(Play, :count) == 0
    refute_received {:stats_updated}

    assert {:ok, play} = Stats.track_play(sound.filename, user.id)

    assert %{played_filename: "beep.mp3", guild_id: "default"} = play
    assert play.sound_id == sound.id
    assert play.user_id == user.id
    assert_received {:stats_updated}
    refute_received {:stats_updated}
  end

  test "plays keep the filename they were played under after a rename", %{
    user: user,
    sound: sound
  } do
    today = Date.utc_today()
    {:ok, _play} = Stats.track_play(sound.filename, user.id)
    sound |> Sound.changeset(%{filename: "renamed.mp3"}) |> Repo.update!()

    assert Stats.get_top_sounds(today, today) == [{"beep.mp3", 1}]
  end

  test "plays survive deleting their sound", %{user: user, sound: sound} do
    {:ok, _play} = Stats.track_play(sound.filename, user.id)
    Repo.delete!(sound)

    assert [{_id, "beep.mp3", "alice", _timestamp}] = Stats.get_recent_plays()
  end

  test "leaderboards rank by play count", %{user: alice, sound: beep} do
    today = Date.utc_today()
    bob = insert_user("bob")
    boop = insert_sound(bob, "boop.mp3")

    for _ <- 1..3, do: {:ok, _play} = Stats.track_play(beep.filename, alice.id)
    {:ok, _play} = Stats.track_play(boop.filename, bob.id)

    assert Stats.get_top_users(today, today) == [{"alice", 3}, {"bob", 1}]
    assert Stats.get_top_sounds(today, today) == [{"beep.mp3", 3}, {"boop.mp3", 1}]
    assert Stats.get_top_users(today, today, limit: 1) == [{"alice", 3}]
  end

  test "recent plays list the newest first", %{user: user, sound: beep} do
    boop = insert_sound(user, "boop.mp3")
    {:ok, _play} = Stats.track_play(beep.filename, user.id)
    {:ok, _play} = Stats.track_play(boop.filename, user.id)

    assert [{_, "boop.mp3", "alice", _}, {_, "beep.mp3", "alice", _}] = Stats.get_recent_plays()
  end

  defp insert_sound(user, filename) do
    %Sound{}
    |> Sound.changeset(%{filename: filename, source_type: "local", user_id: user.id})
    |> Repo.insert!()
  end

  defp insert_user(username) do
    Repo.insert!(%User{username: username, discord_id: "id-#{username}", avatar: "a.jpg"})
  end
end
