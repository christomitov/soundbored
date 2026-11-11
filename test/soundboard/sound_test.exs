defmodule Soundboard.SoundTest do
  use Soundboard.DataCase, async: false

  alias Soundboard.Accounts.User
  alias Soundboard.{Sound, Sounds, UserSoundSetting}

  setup do
    %{user: Repo.insert!(%User{username: "uploader", discord_id: "99", avatar: "a.jpg"})}
  end

  test "changeset rules for uploader, source type, URL, filename and volume" do
    for {attrs, field, message} <- [
          {%{filename: "orphan.mp3", user_id: nil}, :user_id, "can't be blank"},
          {%{source_type: "local"}, :filename, "can't be blank"},
          {%{source_type: "url"}, :url, "can't be blank"},
          {%{source_type: "ftp"}, :source_type, "must be either 'local' or 'url'"},
          {%{filename: "loud.mp3", volume: 1.6}, :volume, "must be less than or equal to 1.5"},
          {%{filename: "quiet.mp3", volume: -0.1}, :volume,
           "must be greater than or equal to 0.0"}
        ] do
      changeset = Sound.changeset(%Sound{}, Map.put_new(attrs, :user_id, 1))

      assert message in Map.get(errors_on(changeset), field, []), inspect(attrs)
    end
  end

  test "recent uploads are this guild's newest first, ten by default", %{user: user} do
    names = for n <- 1..12, do: insert_sound!(user, "upload_#{n}.mp3").filename
    insert_sound!(user, "elsewhere.mp3", %{guild_id: "other-guild"})

    newest_first = Enum.reverse(names)

    assert Enum.map(Sounds.get_recent_uploads(), &elem(&1, 0)) == Enum.take(newest_first, 10)

    assert Enum.map(Sounds.get_recent_uploads(limit: 3), &elem(&1, 0)) ==
             Enum.take(newest_first, 3)

    assert [{"elsewhere.mp3", "uploader", _}] =
             Sounds.get_recent_uploads(guild_id: "other-guild")
  end

  describe "join and leave sounds by Discord id" do
    test "each guild returns its own sound for a user configured in several guilds", %{
      user: user
    } do
      for {flag, lookup} <- [
            is_join_sound: &Sounds.get_user_join_sound_by_discord_id/2,
            is_leave_sound: &Sounds.get_user_leave_sound_by_discord_id/2
          ] do
        for guild <- ["guild-a", "guild-b"] do
          sound = insert_sound!(user, "#{flag}-#{guild}.mp3", %{guild_id: guild})

          %UserSoundSetting{}
          |> UserSoundSetting.changeset(
            Map.put(%{user_id: user.id, sound_id: sound.id, guild_id: guild}, flag, true)
          )
          |> Repo.insert!()
        end

        assert lookup.(user.discord_id, "guild-a") == "#{flag}-guild-a.mp3"
        assert lookup.(user.discord_id, "guild-b") == "#{flag}-guild-b.mp3"
        assert lookup.(user.discord_id, "guild-c") == nil
      end
    end
  end

  defp insert_sound!(user, filename, attrs \\ %{}) do
    %Sound{}
    |> Sound.changeset(
      Map.merge(%{filename: filename, source_type: "local", user_id: user.id}, attrs)
    )
    |> Repo.insert!()
  end
end
