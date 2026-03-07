defmodule Soundboard.Stats do
  @moduledoc """
  Handles the stats of the soundboard.
  """

  import Ecto.Query
  import Ecto.Changeset, only: [add_error: 3, change: 1]

  alias Soundboard.{Accounts.User, PubSubTopics, Repo, Sounds, Stats.Play}

  @type leaderboard_entry :: {String.t(), non_neg_integer()}
  @type recent_play_entry :: {integer(), String.t(), String.t(), NaiveDateTime.t()}

  @spec track_play(String.t(), integer() | nil) :: {:ok, Play.t()} | {:error, Ecto.Changeset.t()}
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

  @spec get_top_users(Date.t(), Date.t(), keyword()) :: [leaderboard_entry()]
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

  @spec get_top_sounds(Date.t(), Date.t(), keyword()) :: [leaderboard_entry()]
  def get_top_sounds(start_date, end_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(p in Play,
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      group_by: p.played_filename,
      select: {p.played_filename, count(p.id)},
      order_by: [desc: count(p.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  @spec get_recent_plays(keyword()) :: [recent_play_entry()]
  def get_recent_plays(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    from(p in Play,
      join: u in User,
      on: p.user_id == u.id,
      select: {p.id, p.played_filename, u.username, p.inserted_at},
      order_by: [desc: p.inserted_at, desc: p.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  @spec reset_weekly_stats() :: :ok | {:error, term()}
  def reset_weekly_stats do
    {week_start, _week_end} = get_week_range()

    from(p in Play, where: p.inserted_at < ^week_start)
    |> Repo.delete_all()

    broadcast_stats_update()
  end

  @spec broadcast_stats_update() :: :ok | {:error, term()}
  def broadcast_stats_update do
    PubSubTopics.broadcast_stats_updated()
  end

  defp insert_play(attrs) do
    %Play{}
    |> Play.changeset(attrs)
    |> Repo.insert()
  end
end
