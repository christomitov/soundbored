defmodule SoundboardWeb.Live.Support.NowPlayingHelpersTest do
  use SoundboardWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Soundboard.{Accounts.User, Repo, Sound}
  alias SoundboardWeb.Live.Support.NowPlayingHelpers

  setup do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "toast-user",
        discord_id: "toast-#{System.unique_integer()}",
        avatar: "a.jpg"
      })
      |> Repo.insert()

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "toast-sound.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert()

    %{user: user, sound: sound}
  end

  test "assign_from_event builds now playing state", %{sound: sound} do
    socket =
      NowPlayingHelpers.assign_from_event(
        NowPlayingHelpers.assign_defaults(%Phoenix.LiveView.Socket{}),
        %{
          filename: sound.filename,
          played_by: "Nick",
          sound_id: sound.id,
          duration_ms: 2500,
          started_at: 1_700_000_000_000
        }
      )

    assert socket.assigns.now_playing.display_name == "toast-sound"
    assert socket.assigns.now_playing.sound_id == sound.id
    assert socket.assigns.now_playing.duration_ms == 2500
    assert socket.assigns.now_playing.played_by == "Nick"
    assert socket.assigns.now_playing.live? == false
  end

  test "assign_from_event marks live youtube sessions", %{user: user} do
    socket =
      NowPlayingHelpers.assign_from_event(
        NowPlayingHelpers.assign_defaults(%Phoenix.LiveView.Socket{}),
        %{
          filename: "24/7 Lo-Fi Beats to Study/Relax To — Extra Long Stream Title",
          played_by: user.username,
          duration_ms: nil,
          started_at: System.system_time(:millisecond),
          live?: true,
          media_type: "youtube",
          thumbnail_url: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
          navigate_to: "/video"
        }
      )

    assert socket.assigns.now_playing.live? == true
    assert socket.assigns.now_playing.duration_ms == nil
    assert socket.assigns.now_playing.media_type == "youtube"
    assert socket.assigns.now_playing.thumbnail_url =~ "dQw4w9WgXcQ"
    assert socket.assigns.now_playing.navigate_to == "/video"

    assert socket.assigns.now_playing.display_name ==
             "24/7 Lo-Fi Beats to Study/Relax To — Extra Long Stream Title"
  end

  test "clear/1 removes now playing state", %{sound: sound} do
    socket =
      NowPlayingHelpers.assign_from_event(
        NowPlayingHelpers.assign_defaults(%Phoenix.LiveView.Socket{}),
        %{filename: sound.filename, played_by: "Nick", sound_id: sound.id}
      )

    assert NowPlayingHelpers.clear(socket).assigns.now_playing == nil
  end

  test "soundboard shows now playing toast on play event", %{conn: conn, sound: sound, user: user} do
    conn = init_test_session(conn, %{user_id: user.id})
    {:ok, view, html} = live(conn, "/")

    refute html =~ ~s(id="desk-transport")

    send(
      view.pid,
      {:sound_played,
       %{
         filename: sound.filename,
         played_by: user.username,
         sound_id: sound.id,
         duration_ms: 4000,
         started_at: System.system_time(:millisecond)
       }}
    )

    html = render(view)
    assert html =~ "toast-sound"
    assert html =~ ~s(id="desk-transport")
    refute html =~ ~s(class="tlabel")
    refute html =~ ~s(class="dot")
    assert html =~ "desk-transport-progress"
  end

  test "soundboard restores now playing toast after remount", %{
    conn: conn,
    sound: sound,
    user: user
  } do
    payload = %{
      filename: sound.filename,
      played_by: user.username,
      sound_id: sound.id,
      duration_ms: 60_000,
      started_at: System.system_time(:millisecond)
    }

    Soundboard.AudioPlayer.set_now_playing(payload)
    # Cast is async; give the player a tick to store state.
    assert_receive_now_playing(payload)

    conn = init_test_session(conn, %{user_id: user.id})
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "toast-sound"
    assert html =~ ~s(id="desk-transport")
    refute html =~ ~s(class="tlabel")
  after
    Soundboard.AudioPlayer.clear_now_playing()
  end

  test "live youtube now playing hides transport progress", %{conn: conn, user: user} do
    conn = init_test_session(conn, %{user_id: user.id})
    {:ok, view, _html} = live(conn, "/")

    send(
      view.pid,
      {:sound_played,
       %{
         filename: "24/7 Lo-Fi Beats to Study/Relax To — Extra Long Stream Title",
         played_by: user.username,
         duration_ms: nil,
         started_at: System.system_time(:millisecond),
         live?: true,
         media_type: "youtube",
         thumbnail_url: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
         navigate_to: "/video"
       }}
    )

    html = render(view)
    assert html =~ "24/7 Lo-Fi Beats to Study/Relax To"
    assert html =~ "tnow-live"
    assert html =~ "transport-art"
    refute html =~ ~s(class="tlabel")
    assert html =~ ~s(href="/video")
    assert html =~ "dQw4w9WgXcQ"
    refute html =~ "desk-transport-progress"
  end

  defp assert_receive_now_playing(payload, attempts \\ 20) do
    cond do
      Soundboard.AudioPlayer.now_playing() == payload ->
        true

      attempts <= 0 ->
        flunk("expected AudioPlayer.now_playing/0 to equal #{inspect(payload)}")

      true ->
        Process.sleep(10)
        assert_receive_now_playing(payload, attempts - 1)
    end
  end
end
