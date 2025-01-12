defmodule Soundboard.Stats do
  import Ecto.Query
  alias Soundboard.{Repo, Stats.Play}

  def track_play(sound_name, user_id) do
    %Play{}
    |> Play.changeset(%{sound_name: sound_name, user_id: user_id})
    |> Repo.insert()
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
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      select: {p.sound_name, u.username, p.inserted_at},
      order_by: [desc: p.inserted_at],
      limit: 10
    )
    |> Repo.all()
  end

  def reset_weekly_stats do
    {week_start, _week_end} = get_week_range()

    from(p in Play, where: p.inserted_at < ^week_start)
    |> Repo.delete_all()

    broadcast_stats_update()
  end

  defp broadcast_stats_update do
    Phoenix.PubSub.broadcast(
      Soundboard.PubSub,
      "soundboard",
      {:stats_updated}
    )
  end
end
