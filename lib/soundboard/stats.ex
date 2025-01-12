defmodule Soundboard.Stats do
  import Ecto.Query
  alias Soundboard.{Repo, Stats.Play, Sound}
  alias Phoenix.PubSub

  @pubsub_topic "soundboard"

  def track_play(sound_name, user_id) do
    result =
      %Play{}
      |> Play.changeset(%{sound_name: sound_name, user_id: user_id})
      |> Repo.insert()

    # Broadcast stats update after tracking play
    broadcast_stats_update()

    result
  end

  defp get_week_range do
    today = Date.utc_today()
    days_since_monday = Date.day_of_week(today, :monday)
    start_date = Date.add(today, -days_since_monday + 1)
    end_date = Date.add(start_date, 6)

    {
      DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"),
      DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")
    }
  end

  def get_top_users(start_date, end_date) do
    from(p in Play,
      join: u in assoc(p, :user),
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      group_by: u.username,
      select: {u.username, count(p.id)},
      order_by: [desc: count(p.id)],
      limit: 10
    )
    |> Repo.all()
  end

  def get_top_sounds(start_date, end_date) do
    from(p in Play,
      join: s in Sound,
      on: s.filename == p.sound_name,
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      group_by: p.sound_name,
      select: {p.sound_name, count(p.id)},
      order_by: [desc: count(p.id)],
      limit: 10
    )
    |> Repo.all()
  end

  def get_recent_plays(start_date, end_date) do
    from(p in Play,
      join: u in assoc(p, :user),
      join: s in Sound,
      on: s.filename == p.sound_name,
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      select: {p.sound_name, u.username, p.inserted_at},
      order_by: [desc: p.inserted_at],
      limit: 10
    )
    |> Repo.all()
  end

  def get_recent_plays(limit) do
    from(p in Play,
      join: u in assoc(p, :user),
      join: s in Sound,
      on: s.filename == p.sound_name,
      select: {p.sound_name, u.username, p.inserted_at},
      order_by: [desc: p.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def reset_weekly_stats do
    {week_start, _week_end} = get_week_range()

    from(p in Play, where: p.inserted_at < ^week_start)
    |> Repo.delete_all()

    broadcast_stats_update()
  end

  def broadcast_stats_update do
    # Broadcast to both channels to ensure all stats are updated
    PubSub.broadcast(Soundboard.PubSub, "stats", {:stats_updated})
    PubSub.broadcast(Soundboard.PubSub, @pubsub_topic, {:stats_updated})
  end
end
