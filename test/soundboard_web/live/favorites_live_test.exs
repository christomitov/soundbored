defmodule SoundboardWeb.FavoritesLiveTest do
  use SoundboardWeb.ConnCase, async: false

  import Mock

  alias Soundboard.{Accounts.User, Favorites, PubSubTopics, Repo, Sound}
  alias Soundboard.Favorites.Favorite

  setup %{conn: conn} do
    user = Repo.insert!(%User{username: "fan", discord_id: "321", avatar: "f.jpg"})
    sound = insert_sound!(user, "liked.mp3")
    second_sound = insert_sound!(user, "unliked.mp3")
    {:ok, _favorite} = Favorites.toggle_favorite(user.id, sound.id)

    %{
      conn: init_test_session(conn, %{user_id: user.id}),
      user: user,
      sound: sound,
      second_sound: second_sound
    }
  end

  defp insert_sound!(user, filename, attrs \\ %{}) do
    %Sound{}
    |> Sound.changeset(
      Map.merge(%{filename: filename, source_type: "local", user_id: user.id}, attrs)
    )
    |> Repo.insert!()
  end

  defp card(filename), do: "[phx-click='play'][phx-value-name='#{filename}']"

  test "redirects unauthenticated users" do
    assert redirected_to(get(build_conn(), "/favorites")) == "/auth/discord"
  end

  test "lists only my favorites", %{conn: conn} do
    {:ok, view, html} = live(conn, "/favorites")

    assert html =~ "1/16 favorites"
    assert has_element?(view, card("liked.mp3"))
    refute has_element?(view, card("unliked.mp3"))
  end

  test "plays a favorite sound", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/favorites")

    with_mock Soundboard.AudioPlayer, play_sound: fn _, _, _ -> :ok end do
      view |> element(card("liked.mp3")) |> render_click()

      assert_called(Soundboard.AudioPlayer.play_sound("liked.mp3", user, "default"))
    end
  end

  test "unstarring removes the sound from favorites", %{conn: conn, user: user, sound: sound} do
    {:ok, view, _html} = live(conn, "/favorites")

    html =
      view
      |> element("[phx-click='toggle_favorite'][phx-value-sound-id='#{sound.id}']")
      |> render_click()

    assert html =~ "Favorites updated!"
    assert html =~ "You currently have no favorites"
    assert Favorites.list_favorites(user.id) == []
  end

  test "a favorite added elsewhere appears", %{conn: conn, user: user, second_sound: second} do
    {:ok, view, _html} = live(conn, "/favorites")

    {:ok, _favorite} = Favorites.toggle_favorite(user.id, second.id)
    PubSubTopics.broadcast_files_updated()

    assert has_element?(view, card("unliked.mp3"))
  end

  test "a play broadcast shows who played what, then clears", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/favorites")

    PubSubTopics.broadcast_sound_played("liked.mp3", "pal")
    assert render(view) =~ "pal played liked.mp3"

    send(view.pid, :clear_flash)
    refute render(view) =~ "pal played"
  end

  test "a playback error is shown", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/favorites")

    PubSubTopics.broadcast_error("Bot is not in a voice channel")

    assert render(view) =~ "Bot is not in a voice channel"
  end

  test "starring past the limit explains the limit", %{conn: conn, user: user} do
    for n <- 1..15 do
      {:ok, _favorite} =
        Favorites.toggle_favorite(user.id, insert_sound!(user, "limit_#{n}.mp3").id)
    end

    over = insert_sound!(user, "one_too_many.mp3")

    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("[phx-click='toggle_favorite'][phx-value-sound-id='#{over.id}']")
      |> render_click()

    assert html =~ "You can only have 16 favorites"
    refute over.id in Favorites.list_favorites(user.id)
  end

  test "another guild's favorites neither count here nor can be starred here", %{
    conn: conn,
    user: user,
    second_sound: second_sound
  } do
    elsewhere =
      for n <- 1..16 do
        sound = insert_sound!(user, "elsewhere_#{n}.mp3", %{guild_id: "other-guild"})
        Repo.insert!(%Favorite{user_id: user.id, sound_id: sound.id})
        sound
      end

    {:ok, view, html} = live(conn, "/favorites")

    assert html =~ "1/16 favorites"
    refute has_element?(view, card("elsewhere_1.mp3"))

    {:ok, board, _html} = live(conn, "/")

    assert board
           |> element("[phx-click='toggle_favorite'][phx-value-sound-id='#{second_sound.id}']")
           |> render_click() =~ "Favorites updated!"

    [foreign | _] = elsewhere

    assert render_click(view, "toggle_favorite", %{"sound-id" => "#{foreign.id}"}) =~
             "Sound does not exist"

    assert Repo.get_by(Favorite, user_id: user.id, sound_id: foreign.id)
  end
end
