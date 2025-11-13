defmodule Soundboard.Stats do
  @moduledoc """
  Handles the stats of the soundboard.
  """
  import Ecto.Query
  alias Phoenix.PubSub
  alias Soundboard.{Accounts.User, Repo, Sound, Stats.Play}

  @stats_topic_prefix "stats:"
  @legacy_pubsub_topic "soundboard"

  def track_play(sound_name, %User{} = user) do
    do_track_play(sound_name, user)
  end

  def track_play(sound_name, user_id) when is_integer(user_id) do
    case Repo.get(User, user_id) do
      %User{} = user -> do_track_play(sound_name, user)
      nil -> {:error, :user_not_found}
    end
  end

  defp do_track_play(sound_name, %User{id: user_id, tenant_id: tenant_id})
       when not is_nil(tenant_id) do
    result =
      %Play{}
      |> Play.changeset(%{sound_name: sound_name, user_id: user_id, tenant_id: tenant_id})
      |> Repo.insert()

    # Broadcast stats update after tracking play
    broadcast_stats_update(tenant_id)

    result
  end

  defp do_track_play(_sound_name, _user), do: {:error, :tenant_missing}

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

  def get_top_users(tenant_id, start_date, end_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(p in Play,
      where: p.tenant_id == ^tenant_id,
      join: u in assoc(p, :user),
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      group_by: u.username,
      select: {u.username, count(p.id)},
      order_by: [desc: count(p.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_top_sounds(tenant_id, start_date, end_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    from(p in Play,
      where: p.tenant_id == ^tenant_id,
      join: s in Sound,
      on: s.filename == p.sound_name,
      where: fragment("DATE(?) BETWEEN ? AND ?", p.inserted_at, ^start_date, ^end_date),
      group_by: p.sound_name,
      select: {p.sound_name, count(p.id)},
      order_by: [desc: count(p.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get_recent_plays(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    # Simple query that gets exactly 5 most recent plays
    from(p in Play,
      where: p.tenant_id == ^tenant_id,
      join: s in Sound,
      on: s.filename == p.sound_name,
      join: u in User,
      on: p.user_id == u.id,
      select: {p.id, s.filename, u.username, p.inserted_at},
      order_by: [desc: p.inserted_at, desc: p.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def reset_weekly_stats(tenant_id) do
    {week_start, _week_end} = get_week_range()

    from(p in Play, where: p.tenant_id == ^tenant_id and p.inserted_at < ^week_start)
    |> Repo.delete_all()

    broadcast_stats_update(tenant_id)
  end

  def broadcast_stats_update(tenant_id) do
    message = {:stats_updated, tenant_id}

    PubSub.broadcast(Soundboard.PubSub, stats_topic(tenant_id), message)
    # Legacy channel for listeners that haven't moved to per-tenant topics yet
    PubSub.broadcast(Soundboard.PubSub, @legacy_pubsub_topic, message)
  end

  def stats_topic(tenant_id) when is_integer(tenant_id) do
    @stats_topic_prefix <> Integer.to_string(tenant_id)
  end
end
