defmodule SoundboardWeb.LeaderboardLiveTest do
  @moduledoc """
  Test for the LeaderboardLive component.
  """
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Soundboard.Accounts.User
  alias Soundboard.{Favorites, Repo, Sound, Stats}
  alias Soundboard.Stats.Play
  alias SoundboardWeb.SoundHelpers

  setup %{conn: conn} do
    # Clean the database before each test
    Repo.delete_all(Play)
    Repo.delete_all(Sound)
    Repo.delete_all(User)

    # Create a test user
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser",
        discord_id: "123",
        avatar: "test.jpg"
      })
      |> Repo.insert()

    # Create test sound with unique name
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test_sound_#{System.unique_integer()}.mp3",
        user_id: user.id,
        source_type: "local"
      })
      |> Repo.insert()

    # Add some stats with the unique sound name
    {:ok, _play} = Stats.track_play(sound.filename, user.id)

    # Add a favorite
    Favorites.toggle_favorite(user.id, sound.id)

    # Set up authenticated conn
    authed_conn =
      conn
      |> Map.replace!(:secret_key_base, SoundboardWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_id: user.id})

    {:ok, conn: authed_conn, user: user, sound: sound}
  end

  test "mounts successfully with user session", %{conn: conn, user: user, sound: sound} do
    {:ok, _view, html} = live(conn, "/stats")
    assert html =~ "Stats"
    assert html =~ "Top Users"
    assert html =~ user.username
    assert html =~ SoundHelpers.display_name(sound.filename)
  end

  test "handles sound_played message", %{conn: conn, sound: sound} do
    {:ok, view, _html} = live(conn, "/stats")

    send(view.pid, {:sound_played, %{filename: sound.filename, played_by: "testuser"}})
    assert render(view) =~ "testuser played #{SoundHelpers.display_name(sound.filename)}"
  end

  test "handles stats_updated message", %{conn: conn, sound: sound} do
    {:ok, view, _html} = live(conn, "/stats")

    send(view.pid, {:stats_updated})
    assert render(view) =~ SoundHelpers.display_name(sound.filename)
  end

  test "handles error message", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stats")

    send(view.pid, {:error, "Test error"})
    assert render(view) =~ "Test error"
  end

  test "handles presence_diff broadcast", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stats")

    send(view.pid, %Phoenix.Socket.Broadcast{
      event: "presence_diff",
      payload: %{joins: %{}, leaves: %{}}
    })

    assert render(view) =~ "Top Users"
  end

  test "handles play_sound event", %{conn: conn, user: user, sound: sound} do
    {:ok, view, _html} = live_as_user(conn, user)

    html = render_click(view, "play_sound", %{"sound" => sound.filename})
    assert html =~ SoundHelpers.display_name(sound.filename)
  end

  test "handles toggle_favorite event", %{conn: conn, user: user, sound: sound} do
    {:ok, view, _html} = live_as_user(conn, user)

    html = render_click(view, "toggle_favorite", %{"sound" => sound.filename})
    assert html =~ SoundHelpers.display_name(sound.filename)
  end

  test "handles week navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stats")

    html = render_click(view, "previous_week")
    assert html =~ "Stats"

    html = render_click(view, "next_week")
    assert html =~ "Stats"
  end

  defp live_as_user(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> put_session(:user_id, user.id)
    |> live("/stats")
  end
end
