defmodule Soundboard.Sounds.SoundSettingsTest do
  use Soundboard.DataCase, async: false

  alias Soundboard.{Accounts.User, Sound, UserSoundSetting}

  test "a user has at most one join and one leave sound per guild" do
    user = Repo.insert!(%User{username: "settings", discord_id: "77", avatar: "a.jpg"})

    for flag <- [:is_join_sound, :is_leave_sound] do
      [first, second, elsewhere] =
        for {name, guild} <- [{"a", "default"}, {"b", "default"}, {"c", "other-guild"}] do
          sound =
            %Sound{}
            |> Sound.changeset(%{
              filename: "#{flag}-#{name}.mp3",
              source_type: "local",
              user_id: user.id,
              guild_id: guild
            })
            |> Repo.insert!()

          UserSoundSetting.changeset(
            %UserSoundSetting{},
            Map.put(%{user_id: user.id, sound_id: sound.id, guild_id: guild}, flag, true)
          )
        end

      Repo.insert!(first)
      Repo.insert!(elsewhere)

      assert_raise Ecto.ConstraintError, fn -> Repo.insert!(second) end
    end
  end
end
