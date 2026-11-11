defmodule SoundboardWeb.FavoritesLiveTest do
  use SoundboardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.{Favorites, Repo, Sound}
  alias SoundboardWeb.SoundHelpers

  setup %{conn: conn} do
    Repo.delete_all(Sound)
    Repo.delete_all(User)

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "favorite_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "favorite.jpg"
      })
      |> Repo.insert()

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "favorite_#{System.unique_integer([:positive])}.mp3",
        user_id: user.id,
        source_type: "local"
      })
      |> Repo.insert()

    {:ok, second_sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "favorite_extra_#{System.unique_integer([:positive])}.mp3",
        user_id: user.id,
        source_type: "local"
      })
      |> Repo.insert()

    {:ok, _favorite} = Favorites.toggle_favorite(user.id, sound.id)

    authed_conn =
      conn
      |> Map.replace!(:secret_key_base, SoundboardWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_id: user.id})

    %{conn: authed_conn, user: user, sound: sound, second_sound: second_sound}
  end

  test "redirects unauthenticated users", _context do
    conn =
      get(build_conn(), "/favorites")

    assert redirected_to(conn) == "/auth/discord"
  end

  test "renders favorite sounds for the current user", %{conn: conn, sound: sound} do
    {:ok, _view, html} = live(conn, "/favorites")

    assert html =~ "Favorites"
    assert html =~ SoundHelpers.display_name(sound.filename)
  end

  test "plays a favorite sound", %{conn: conn, user: user, sound: sound} do
    {:ok, view, _html} = live(conn, "/favorites")

    with_mock Soundboard.AudioPlayer, play_sound: fn _, _, _ -> :ok end do
      view
      |> element("[phx-click='play'][phx-value-name='#{sound.filename}']")
      |> render_click()

      assert_called(Soundboard.AudioPlayer.play_sound(sound.filename, user, :_))
    end
  end

  test "toggle_favorite removes a sound from favorites", %{conn: conn, sound: sound} do
    {:ok, view, _html} = live(conn, "/favorites")

    html =
      view
      |> element("[phx-click='toggle_favorite'][phx-value-sound-id='#{sound.id}']")
      |> render_click()

    assert html =~ "Favorites updated!"
    assert html =~ "You currently have no favorites"
  end

  test "files_updated refreshes the favorites list", %{
    conn: conn,
    user: user,
    second_sound: second_sound
  } do
    {:ok, view, _html} = live(conn, "/favorites")

    {:ok, _favorite} = Favorites.toggle_favorite(user.id, second_sound.id)
    send(view.pid, {:files_updated})

    assert render(view) =~ SoundHelpers.display_name(second_sound.filename)
  end

  test "stats_updated refreshes the favorites list", %{
    conn: conn,
    user: user,
    second_sound: second_sound
  } do
    {:ok, view, _html} = live(conn, "/favorites")

    {:ok, _favorite} = Favorites.toggle_favorite(user.id, second_sound.id)
    send(view.pid, {:stats_updated})

    assert render(view) =~ SoundHelpers.display_name(second_sound.filename)
  end

  test "a play broadcast shows who played what, then clears", %{conn: conn, sound: sound} do
    {:ok, view, _html} = live(conn, "/favorites")

    send(view.pid, {:sound_played, %{filename: sound.filename, played_by: "pal"}})
    assert render(view) =~ "pal played #{sound.filename}"

    send(view.pid, :clear_flash)
    refute render(view) =~ "pal played"
  end

  test "a bare play broadcast credits the current user", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/favorites")

    send(view.pid, {:sound_played, "boom.mp3"})

    assert render(view) =~ "#{user.username} played boom.mp3"
  end

  test "a playback error is shown", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/favorites")

    send(view.pid, {:error, "Bot is not in a voice channel"})

    assert render(view) =~ "Bot is not in a voice channel"
  end

  test "starring past the limit explains the limit", %{conn: conn, user: user} do
    for n <- 1..(Favorites.max_favorites() - 1) do
      extra =
        %Sound{}
        |> Sound.changeset(%{filename: "limit_#{n}.mp3", user_id: user.id, source_type: "local"})
        |> Repo.insert!()

      {:ok, _favorite} = Favorites.toggle_favorite(user.id, extra.id)
    end

    over =
      %Sound{}
      |> Sound.changeset(%{filename: "one_too_many.mp3", user_id: user.id, source_type: "local"})
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("[phx-click='toggle_favorite'][phx-value-sound-id='#{over.id}']")
      |> render_click()

    assert html =~ "You can only have #{Favorites.max_favorites()} favorites"
  end
end
