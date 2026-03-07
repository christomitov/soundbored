defmodule Soundboard.Stats do
  @moduledoc """
  Handles the stats of the soundboard.
  """
  import Ecto.Query
  import Ecto.Changeset, only: [add_error: 3, change: 1]

  alias Soundboard.{Accounts.User, PubSubTopics, Repo, Sounds, Stats.Play}

  def track_play(sound_name, user_id) do
    with {:ok, sound_id} <- Sounds.fetch_sound_id(sound_name),
         {:ok, play} <-
           insert_play(%{played_filename: sound_name, sound_id: sound_id, user_id: user_id}) do
      broadcast_stats_update()
      {:ok, play}
    else
      :error -> {:error, add_error(change(%Play{}), :sound_id, "can't be blank")}
      {:error, _changeset} = result -> result
    end
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

  def get_top_users(start_date, end_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(p in Play,
      join: u in assoc(p, :user),
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      group_by: u.username,
      select: {u.username, count(p.id)},
      order_by: [desc: count(p.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_top_sounds(start_date, end_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(p in Play,
      left_join: s in assoc(p, :sound),
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      group_by: fragment("COALESCE(?, ?)", s.filename, p.played_filename),
      select: {fragment("COALESCE(?, ?)", s.filename, p.played_filename), count(p.id)},
      order_by: [desc: count(p.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_recent_plays(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    # Preserve historical plays even if the linked sound was renamed or deleted.
    from(p in Play,
      left_join: s in assoc(p, :sound),
      join: u in User,
      on: p.user_id == u.id,
      select:
        {p.id, fragment("COALESCE(?, ?)", s.filename, p.played_filename), u.username,
         p.inserted_at},
      order_by: [desc: p.inserted_at, desc: p.id],
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
    PubSubTopics.broadcast_stats_updated()
  end

  defp insert_play(attrs) do
    %Play{}
    |> Play.changeset(attrs)
    |> Repo.insert()
  end
end
