defmodule SoundboardWeb.StatsLiveTest do
  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.{Accounts.User, Favorites, PubSubTopics, Repo, Sound, Stats}

  setup %{conn: conn} do
    user = Repo.insert!(%User{username: "testuser", discord_id: "123", avatar: "test.jpg"})
    sound = insert_sound!(user, "stats_sound.mp3")
    {:ok, _play} = Stats.track_play(sound.filename, user.id)
    {:ok, _favorite} = Favorites.toggle_favorite(user.id, sound.id)

    {:ok, conn: init_test_session(conn, %{user_id: user.id}), user: user, sound: sound}
  end

  defp insert_sound!(user, filename, attrs \\ %{}) do
    %Sound{}
    |> Sound.changeset(
      Map.merge(%{filename: filename, source_type: "local", user_id: user.id}, attrs)
    )
    |> Repo.insert!()
  end

  defp top_sound(filename), do: "[id='play-top-#{filename}']"

  defp week_label({start_date, end_date}),
    do: "#{Calendar.strftime(start_date, "%b %d")} - #{Calendar.strftime(end_date, "%b %d, %Y")}"

  defp week_of(date) do
    start_date = Date.add(date, 1 - Date.day_of_week(date, :monday))
    {start_date, Date.add(start_date, 6)}
  end

  test "shows this week's top sounds and users, with avatars, and recent uploads", %{
    conn: conn,
    user: user,
    sound: sound
  } do
    offline = Repo.insert!(%User{username: "offline", discord_id: "456", avatar: "off.jpg"})
    {:ok, _play} = Stats.track_play(sound.filename, offline.id)
    {:ok, _play} = Stats.track_play(sound.filename, user.id)

    {:ok, view, _html} = live(conn, "/stats")

    assert has_element?(view, top_sound("stats_sound.mp3"), "3 plays")
    assert has_element?(view, "#user-stat-testuser", "2 plays")
    assert has_element?(view, "#user-stat-offline", "1 plays")
    assert has_element?(view, "#user-stat-offline img[src='off.jpg']")
    assert has_element?(view, "[id='play-upload-stats_sound.mp3']")
  end

  test "a guild with no plays or uploads shows empty lists", %{conn: conn, sound: sound} do
    Repo.delete!(sound)
    Repo.delete_all(Soundboard.Stats.Play)

    {:ok, view, _html} = live(conn, "/stats")

    refute has_element?(view, "[id^='play-top-']")
    refute has_element?(view, "[id^='user-stat-']")
    refute has_element?(view, "[id^='play-upload-']")
  end

  test "plays keep the name the sound had when it was played", %{conn: conn, sound: sound} do
    sound |> Sound.changeset(%{filename: "renamed.mp3"}) |> Repo.update!()

    {:ok, view, _html} = live(conn, "/stats")

    assert has_element?(view, top_sound("stats_sound.mp3"), "1 plays")
    assert has_element?(view, "#recent_plays", "stats_sound")
    refute has_element?(view, "#recent_plays", "renamed")
    assert has_element?(view, "[id='play-upload-renamed.mp3']")
  end

  test "a new play elsewhere updates the leaderboard and shows who played it", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, "/stats")
    insert_sound!(user, "fresh.mp3")

    {:ok, _play} = Stats.track_play("fresh.mp3", user.id)
    PubSubTopics.broadcast_sound_played("fresh.mp3", "pal")

    assert has_element?(view, top_sound("fresh.mp3"), "1 plays")
    assert has_element?(view, "#recent_plays", "fresh")
    assert render(view) =~ "pal played fresh"
  end

  test "a playback error is shown", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stats")

    PubSubTopics.broadcast_error("Test error")

    assert render(view) =~ "Test error"
  end

  test "clicking a top sound plays it", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/stats")

    with_mock Soundboard.AudioPlayer, play_sound: fn _, _, _ -> :ok end do
      view |> element(top_sound("stats_sound.mp3")) |> render_click()

      assert_called(Soundboard.AudioPlayer.play_sound("stats_sound.mp3", user, "default"))
    end
  end

  test "the heart toggles the favorite", %{conn: conn, user: user, sound: sound} do
    {:ok, view, _html} = live(conn, "/stats")

    assert view |> element("[id='favorite-stats_sound.mp3']") |> render_click() =~
             "Favorites updated!"

    assert Favorites.list_favorites(user.id) == []

    view |> element("[id='favorite-stats_sound.mp3']") |> render_click()
    assert Favorites.list_favorites(user.id) == [sound.id]
  end

  describe "weeks" do
    test "the arrows move between weeks, never past this one", %{conn: conn} do
      this_week = week_of(Date.utc_today())
      last_week = week_of(Date.add(Date.utc_today(), -7))
      {:ok, view, _html} = live(conn, "/stats")

      assert render_click(view, "next_week") =~ week_label(this_week)

      view |> element("[phx-click='previous_week']") |> render_click()
      assert render(view) =~ week_label(last_week)
      refute has_element?(view, top_sound("stats_sound.mp3"))

      view |> element("[phx-click='next_week']") |> render_click()
      assert render(view) =~ week_label(this_week)
      assert has_element?(view, top_sound("stats_sound.mp3"))
    end

    test "the week picker moves to the picked week", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/stats")
      target = Date.add(Date.utc_today(), -7)

      view
      |> element("form[phx-change='select_week']")
      |> render_change(%{"week" => Date.to_iso8601(target)})

      assert render(view) =~ week_label(week_of(target))
      refute has_element?(view, top_sound("stats_sound.mp3"))
    end

    test "the week picker ignores future, empty and malformed dates", %{conn: conn} do
      this_week = week_of(Date.utc_today())
      future = Date.to_iso8601(Date.add(Date.utc_today(), 14))
      {:ok, view, _html} = live(conn, "/stats")

      for week <- [future, "", "not-a-date"] do
        html =
          view |> element("form[phx-change='select_week']") |> render_change(%{"week" => week})

        assert html =~ week_label(this_week)
        assert has_element?(view, top_sound("stats_sound.mp3"))
      end
    end

    test "the hourly check moves a page left open on last week's current week forward", %{
      conn: conn
    } do
      this_week = week_of(Date.utc_today())
      last_week = week_of(Date.add(Date.utc_today(), -7))
      {:ok, view, _html} = live(conn, "/stats")

      :sys.replace_state(view.pid, fn state ->
        assigns = %{
          state.socket.assigns
          | current_week: last_week,
            selected_week: last_week,
            __changed__: %{current_week: true, selected_week: true}
        }

        put_in(state.socket.assigns, assigns)
      end)

      send(view.pid, :check_week_rollover)

      assert render(view) =~ week_label(this_week)
      assert has_element?(view, top_sound("stats_sound.mp3"), "1 plays")
    end
  end

  test "plays and uploads from another guild never show, and favorites resolve here", %{
    conn: conn,
    user: user,
    sound: sound
  } do
    outsider =
      Repo.insert!(%User{username: "outsider", discord_id: "outsider-1", avatar: "o.jpg"})

    elsewhere = insert_sound!(outsider, "elsewhere.mp3", %{guild_id: "other-guild"})
    twin = insert_sound!(outsider, sound.filename, %{guild_id: "other-guild"})
    {:ok, _play} = Stats.track_play(elsewhere.filename, outsider.id, "other-guild")
    {:ok, _play} = Stats.track_play(twin.filename, outsider.id, "other-guild")

    {:ok, view, html} = live(conn, "/stats")

    refute html =~ "elsewhere"
    refute html =~ "outsider"
    assert has_element?(view, top_sound("stats_sound.mp3"), "1 plays")

    view |> element("[id='favorite-stats_sound.mp3']") |> render_click()

    assert Favorites.list_favorites(user.id) == []
    refute Repo.get_by(Soundboard.Favorites.Favorite, sound_id: twin.id)
  end
end
