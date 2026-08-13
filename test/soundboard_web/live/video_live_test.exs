defmodule SoundboardWeb.VideoLiveTest do
  use SoundboardWeb.ConnCase

  alias Soundboard.Accounts.User
  alias Soundboard.{PubSubTopics, Repo, VideoPlayer}

  setup %{conn: conn} do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "video_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "test.jpg"
      })
      |> Repo.insert()

    authed_conn =
      conn
      |> Map.replace!(:secret_key_base, SoundboardWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{user_id: user.id})

    VideoPlayer.stop()
    Process.sleep(20)

    %{conn: authed_conn, user: user}
  end

  test "renders video tab with player and up-next queue", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/video")

    assert html =~ "Video"
    assert html =~ "YouTube"
    assert html =~ "shared-video-player"
    assert html =~ "Up next"
    assert html =~ "Nothing queued"
  end

  test "navbar shows live indicator when video session is active", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/video")

    PubSubTopics.broadcast_video_state(%{
      id: "abc",
      status: :ready,
      title: "Demo",
      host_username: "host",
      host_user_id: 1,
      playing?: true,
      position_ms: 0
    })

    html = render(view)
    assert html =~ "LIVE"
    assert html =~ "animate-ping"
  end

  test "queued video shows metadata skeletons until its title arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/video")

    item = %{
      id: "queued-1",
      url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      youtube_id: "dQw4w9WgXcQ",
      title: nil,
      thumbnail_url: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
      queued_by_username: "video-user",
      prefetch_status: :fetching,
      progress_percent: 30,
      error: nil
    }

    PubSubTopics.broadcast_video_queue([item])
    html = render(view)

    assert html =~ "Loading video thumbnail"
    assert html =~ "Loading video title"
    assert html =~ "video-queue-title-skeleton"
    assert html =~ "Video preparation progress"
    assert html =~ ~s(aria-valuenow="30")
    assert html =~ "30%"
    refute html =~ item.url
    refute html =~ item.thumbnail_url

    PubSubTopics.broadcast_video_queue([
      %{item | title: "Never Gonna Give You Up", prefetch_status: :ready}
    ])

    html = render(view)
    assert html =~ "Never Gonna Give You Up"
    assert html =~ item.thumbnail_url
    refute html =~ "Loading video title"
    refute html =~ "Video preparation progress"
  end

  test "settings page shows youtube cookies section", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/settings")

    assert html =~ "YouTube Cookies"
    assert html =~ "cookies.txt"
  end
end
