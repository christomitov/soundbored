# Demo fixture data for local testing and marketing screenshots.
#
#   mix run priv/repo/demo_seeds.exs           # seed demo data (most-sounds guild)
#   DELETE=1 mix run priv/repo/demo_seeds.exs  # tear down everything the script created
#
# Demo users have `demo-` prefixed discord ids so teardown is unambiguous.
# Sounds are url-backed (source_type: "url"), so no audio files are needed;
# the URLs point at example.com and are only placeholders for the UI.

alias Soundboard.Accounts.User
alias Soundboard.Favorites.Favorite
alias Soundboard.Repo
alias Soundboard.Sound
alias Soundboard.SoundTag
alias Soundboard.Stats.Play
alias Soundboard.Tag
alias Soundboard.Tenants.Guild

import Ecto.Query

# mix run --no-start skips the whole app (the dev endpoint fights for port 4000
# while the dev server runs), so bring up just the Repo when it is not running.
unless Process.whereis(Repo), do: {:ok, _} = Repo.start_link()

demo_users = [
  {"meme_lord", "demo-1001"},
  {"sound_gremlin", "demo-1002"},
  {"vc_grandma", "demo-1003"}
]

demo_sounds = [
  {"airhorn.mp3", ["funny", "gaming"], 9},
  {"bruh.mp3", ["funny"], 7},
  {"sad-violin.mp3", ["funny", "reaction"], 5},
  {"tada-fanfare.mp3", ["funny", "music"], 4},
  {"drum-roll.mp3", ["music", "gaming"], 3},
  {"explosion-boom.mp3", ["reaction", "gaming"], 3},
  {"victory-theme.mp3", ["music", "gaming"], 3},
  {"cricket-chirp.mp3", ["funny", "reaction"], 2},
  {"ding-notification.mp3", ["alerts"], 2},
  {"alarm-siren.mp3", ["alerts"], 2},
  {"lofi-beat.mp3", ["music"], 2},
  {"doorbell.mp3", ["alerts"], 1}
]

if System.get_env("DELETE") == "1" do
  demo_user_ids = User |> where([u], like(u.discord_id, "demo-%")) |> select([u], u.id)

  Repo.delete_all(from p in Play, where: p.user_id in subquery(demo_user_ids))
  Repo.delete_all(from f in Favorite, where: f.user_id in subquery(demo_user_ids))
  Repo.delete_all(from u in User, where: like(u.discord_id, "demo-%"))

  demo_guild_ids =
    Guild |> where([g], like(g.discord_guild_id, "demo-%")) |> select([g], g.discord_guild_id)

  demo_sound_ids = from(s in Sound, where: s.guild_id in subquery(demo_guild_ids), select: s.id)

  Repo.delete_all(from st in SoundTag, where: st.sound_id in subquery(demo_sound_ids))
  Repo.delete_all(from p in Play, where: p.sound_id in subquery(demo_sound_ids))
  Repo.delete_all(from f in Favorite, where: f.sound_id in subquery(demo_sound_ids))
  Repo.delete_all(from s in Sound, where: s.id in subquery(demo_sound_ids))
  Repo.delete_all(from g in Guild, where: g.discord_guild_id in subquery(demo_guild_ids))

  IO.puts("Demo data torn down.")
else
  users =
    Map.new(demo_users, fn {name, discord_id} ->
      user =
        Repo.get_by(User, discord_id: discord_id) ||
          Repo.insert!(%User{discord_id: discord_id, username: name})

      {name, user}
    end)

  # Seed into the guild that already has the most sounds; on an empty DB,
  # create one demo guild so the script always leaves usable data behind.
  {guild, created?} =
    case Repo.one(
           from g in Guild,
             join: s in Sound,
             on: s.guild_id == g.discord_guild_id,
             group_by: g.id,
             order_by: [desc: count(s.id)],
             limit: 1,
             select: g
         ) do
      nil ->
        {Repo.insert!(%Guild{
           discord_guild_id: "demo-guild-1",
           name: "Demo Server",
           slug: "demo"
         }), true}

      guild ->
        {guild, false}
    end

  sounds =
    if created? do
      uploader_cycle = Enum.map(demo_users, fn {name, _} -> users[name] end)

      sounds =
        Enum.with_index(demo_sounds, fn {filename, tags, _weight}, i ->
          sound =
            Repo.insert!(%Sound{
              filename: filename,
              url: "https://example.com/sounds/" <> filename,
              source_type: "url",
              guild_id: guild.discord_guild_id,
              user_id: Enum.at(uploader_cycle, rem(i, 3)).id
            })

          Enum.each(tags, fn tag_name ->
            tag = Repo.get_by(Tag, name: tag_name) || Repo.insert!(%Tag{name: tag_name})
            Repo.insert!(%SoundTag{sound_id: sound.id, tag_id: tag.id})
          end)

          sound
        end)

      sounds
    else
      Repo.all(from s in Sound, where: s.guild_id == ^guild.discord_guild_id)
    end

  # Top Sounds and Top Users are scoped to the displayed week (starting Monday
  # 00:00 UTC), so the seeded plays must land inside it. Recent Plays is not
  # week-scoped and shows whatever is newest.
  now = DateTime.utc_now() |> DateTime.truncate(:second)
  days_since_monday = Date.day_of_week(now) - 1
  week_start = DateTime.add(now, -days_since_monday * 24 * 3600)
  span = max(DateTime.diff(now, week_start), 3600)

  existing_plays =
    Repo.one(
      from p in Play,
        join: s in Sound,
        on: p.sound_id == s.id,
        where: s.guild_id == ^guild.discord_guild_id and p.inserted_at >= ^week_start,
        select: count(p.id)
    )

  if existing_plays == 0 and sounds != [] do
    uploaders = Enum.map(demo_users, fn {name, _} -> users[name] end)

    plays =
      Enum.flat_map(demo_sounds, fn {filename, _tags, weight} ->
        sound = Enum.find(sounds, &(&1.filename == filename)) || Enum.random(sounds)

        Enum.map(1..weight, fn i ->
          user = Enum.at(uploaders, rem(i, 3))
          offset = :rand.uniform(span)

          ts =
            DateTime.add(DateTime.utc_now(), -offset)
            |> DateTime.truncate(:second)
            |> DateTime.to_naive()

          %Play{
            played_filename: sound.filename,
            sound_id: sound.id,
            user_id: user.id,
            inserted_at: ts,
            updated_at: ts
          }
        end)
      end)

    Enum.each(plays, &Repo.insert!/1)
    IO.puts("#{length(plays)} plays seeded into #{guild.name}.")
  else
    IO.puts("Plays already exist for #{guild.name} this week; skipping play seeds.")
  end

  case Repo.get_by(User, username: "e2e-user") do
    nil ->
      IO.puts("No e2e-user found; favorites skipped.")

    user ->
      Enum.each(Enum.take(sounds, 3), fn sound ->
        unless Repo.get_by(Favorite, user_id: user.id, sound_id: sound.id) do
          Repo.insert!(%Favorite{user_id: user.id, sound_id: sound.id})
        end
      end)

      IO.puts("Favorites seeded for e2e-user.")
  end

  IO.puts("Demo data seeded into #{guild.name}.")
end
