defmodule SoundboardWeb.SoundboardLive.BrowseTest do
  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.{Accounts.User, Favorites, PubSubTopics, Repo, Sound, Tag}
  alias SoundboardWeb.Presence

  setup %{conn: conn} do
    user = Repo.insert!(%User{username: "testuser", discord_id: "123", avatar: "test.jpg"})
    sound = insert_sound!(user, "test.mp3")

    {:ok, conn: init_test_session(conn, %{user_id: user.id}), user: user, sound: sound}
  end

  defp insert_sound!(user, filename, attrs \\ %{}) do
    %Sound{}
    |> Sound.changeset(
      Map.merge(%{filename: filename, source_type: "local", user_id: user.id}, attrs)
    )
    |> Repo.insert!()
  end

  defp tag!(name), do: Repo.insert!(%Tag{name: name})

  defp card(filename), do: "[phx-click='play'][phx-value-name='#{filename}']"

  defp pick_tag(view, name),
    do: view |> element("div.hidden.sm\\:flex button[phx-value-tag='#{name}']") |> render_click()

  describe "listing" do
    test "only the current guild's sounds are listed", %{conn: conn, user: user} do
      insert_sound!(user, "elsewhere.mp3", %{guild_id: "other-guild"})

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, card("test.mp3"))
      refute has_element?(view, card("elsewhere.mp3"))
    end

    test "a new upload elsewhere appears in the list", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, "/")

      insert_sound!(user, "fresh.mp3")
      PubSubTopics.broadcast_files_updated()

      assert has_element?(view, card("fresh.mp3"))
    end
  end

  describe "search and tags" do
    test "search matches names and tag names, ignoring case", %{conn: conn, user: user} do
      insert_sound!(user, "other.mp3", %{tags: [tag!("meme")]})
      {:ok, view, _html} = live(conn, "/")

      view |> element("form") |> render_change(%{"query" => "TEST"})
      assert has_element?(view, card("test.mp3"))
      refute has_element?(view, card("other.mp3"))

      view |> element("form") |> render_change(%{"query" => "Meme"})
      assert has_element?(view, card("other.mp3"))
      refute has_element?(view, card("test.mp3"))
    end

    test "the selected tag shows as a removable chip in the search bar", %{
      conn: conn,
      user: user
    } do
      insert_sound!(user, "funny.mp3", %{tags: [tag!("funny")]})
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#sound-search-input[phx-hook='SearchBackspace']")
      refute has_element?(view, "button[phx-click='clear_tag_filters']")

      pick_tag(view, "funny")
      refute has_element?(view, card("test.mp3"))

      view |> element("button[phx-click='clear_tag_filters']") |> render_click()

      assert has_element?(view, card("test.mp3"))
      assert has_element?(view, card("funny.mp3"))
      refute has_element?(view, "button[phx-click='clear_tag_filters']")
    end

    test "clicking the selected tag again clears it", %{conn: conn, user: user} do
      insert_sound!(user, "funny.mp3", %{tags: [tag!("funny")]})
      {:ok, view, _html} = live(conn, "/")

      pick_tag(view, "funny")
      refute has_element?(view, card("test.mp3"))

      pick_tag(view, "funny")
      assert has_element?(view, card("test.mp3"))
    end

    test "typing narrows within the selected tag", %{conn: conn, user: user} do
      insert_sound!(user, "funny.mp3", %{tags: [tag!("funny")]})
      insert_sound!(user, "fun_untagged.mp3")
      {:ok, view, _html} = live(conn, "/")

      pick_tag(view, "funny")
      view |> element("form[phx-change='search']") |> render_change(%{"query" => "fun"})

      assert has_element?(view, card("funny.mp3"))
      refute has_element?(view, card("fun_untagged.mp3"))
      refute has_element?(view, card("test.mp3"))
    end

    test "pressing enter in search clears the selected tag", %{conn: conn, user: user} do
      insert_sound!(user, "funny.mp3", %{tags: [tag!("funny")]})
      {:ok, view, _html} = live(conn, "/")

      pick_tag(view, "funny")
      refute has_element?(view, card("test.mp3"))

      view |> element("form[phx-submit='commit_search']") |> render_submit(%{"query" => "test"})

      assert has_element?(view, card("test.mp3"))
      refute has_element?(view, card("funny.mp3"))
    end

    test "each tag is offered once with its sound count, highlighted when selected", %{
      conn: conn,
      user: user,
      sound: sound
    } do
      meme = tag!("meme")
      insert_sound!(user, "other.mp3", %{tags: [meme]})

      sound
      |> Repo.preload(:tags)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:tags, [meme])
      |> Repo.update!()

      {:ok, view, _html} = live(conn, "/")
      button = "div.hidden.sm\\:flex button[phx-value-tag='meme']"

      assert view |> element(button) |> render() =~ "(2)"
      refute view |> element(button) |> render() =~ "bg-blue-100"

      pick_tag(view, "meme")
      assert view |> element(button) |> render() =~ "bg-blue-100"
    end

    test "more than twelve tags collapse behind a toggle", %{conn: conn, sound: sound} do
      tags = for n <- 1..13, do: tag!("tag#{String.pad_leading("#{n}", 2, "0")}")

      sound
      |> Repo.preload(:tags)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:tags, tags)
      |> Repo.update!()

      {:ok, view, _html} = live(conn, "/")
      toggle = "[phx-click='toggle_tag_list']"
      last_tag = ".sm\\:hidden [phx-click='toggle_tag_filter'][phx-value-tag='tag13']"

      refute has_element?(view, last_tag)
      assert view |> element(toggle, "Show more tags") |> render_click()
      assert has_element?(view, last_tag)
      assert view |> element(toggle, "Show fewer tags") |> render_click()
      refute has_element?(view, last_tag)
    end
  end

  describe "playing" do
    test "clicking a sound plays it in the current guild as the signed-in user", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, "/")

      with_mock Soundboard.AudioPlayer, play_sound: fn _, _, _ -> :ok end do
        view |> element(card("test.mp3")) |> render_click()

        assert_called(Soundboard.AudioPlayer.play_sound("test.mp3", user, "default"))
      end
    end

    test "play random picks from the current search results", %{conn: conn, user: user} do
      insert_sound!(user, "filtered.mp3")
      {:ok, view, _html} = live(conn, "/")

      view |> element("form") |> render_change(%{"query" => "filtered"})

      with_mock Soundboard.AudioPlayer, play_sound: fn _, _, _ -> :ok end do
        view |> element("[phx-click='play_random']") |> render_click()

        assert_called(Soundboard.AudioPlayer.play_sound("filtered.mp3", :_, :_))
      end
    end

    test "play random picks from the selected tag", %{conn: conn, user: user} do
      insert_sound!(user, "funny.mp3", %{tags: [tag!("funny")]})
      {:ok, view, _html} = live(conn, "/")

      pick_tag(view, "funny")

      with_mock Soundboard.AudioPlayer, play_sound: fn _, _, _ -> :ok end do
        view |> element("[phx-click='play_random']") |> render_click()

        assert_called(Soundboard.AudioPlayer.play_sound("funny.mp3", :_, :_))
      end
    end

    test "stop stops the bot and every browser player", %{conn: conn} do
      with_mock Soundboard.AudioPlayer, stop_sound: fn _guild_id -> :ok end do
        {:ok, view, _html} = live(conn, "/")

        view |> element("[phx-click='stop_sound']") |> render_click()

        assert_push_event(view, "stop-all-sounds", %{})
        assert_called(Soundboard.AudioPlayer.stop_sound("default"))
      end
    end

    test "a play elsewhere shows who played what", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      PubSubTopics.broadcast_sound_played("test.mp3", "someone")

      assert render(view) =~ "someone played test.mp3"
    end

    test "a playback error is shown, and the flash clears", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      PubSubTopics.broadcast_error("Bot is not in a voice channel")
      assert render(view) =~ "Bot is not in a voice channel"

      send(view.pid, :clear_flash)
      refute render(view) =~ "Bot is not in a voice channel"
    end
  end

  test "starring a sound adds it to favorites", %{conn: conn, user: user, sound: sound} do
    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("[phx-click='toggle_favorite'][phx-value-sound-id='#{sound.id}']")
      |> render_click()

    assert html =~ "Favorites updated!"
    assert Favorites.list_favorites(user.id) == [sound.id]
  end

  test "people online appear in the navbar, each listed once", %{conn: conn} do
    {:ok, _first_tab, _html} = live(conn, "/")
    {:ok, second_tab, _html} = live(conn, "/")
    Phoenix.PubSub.subscribe(Soundboard.PubSub, "soundboard:presence")

    {:ok, _ref} =
      Presence.track(self(), "soundboard:presence", "pal-socket", %{
        user: %{username: "pal", avatar: "pal.jpg"},
        online_at: System.system_time(:second)
      })

    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}
    html = render(second_tab)

    assert has_element?(second_tab, "#user-pal")

    assert html |> LazyHTML.from_fragment() |> LazyHTML.query("#user-testuser") |> Enum.count() ==
             1
  end
end
