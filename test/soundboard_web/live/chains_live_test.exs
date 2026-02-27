defmodule SoundboardWeb.ChainsLiveTest do
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  import Mock

  alias Soundboard.Accounts.User
  alias Soundboard.{Chains, Repo, Sound}

  setup %{conn: conn} do
    Repo.delete_all(Soundboard.Chains.ChainItem)
    Repo.delete_all(Soundboard.Chains.Chain)
    Repo.delete_all(Sound)
    Repo.delete_all(User)

    user = insert_user(%{username: "owner", discord_id: "owner-123"})
    other_user = insert_user(%{username: "other", discord_id: "other-456"})

    sound_a = insert_sound(user, %{filename: "alpha.mp3"})
    sound_b = insert_sound(user, %{filename: "beta.mp3"})
    sound_c = insert_sound(other_user, %{filename: "gamma.mp3"})

    {:ok, my_chain} =
      Chains.create_chain(user.id, %{
        name: "My Chain",
        sound_ids: [sound_a.id, sound_b.id],
        is_public: false
      })

    {:ok, public_chain} =
      Chains.create_chain(other_user.id, %{
        name: "Public Chain",
        sound_ids: [sound_c.id],
        is_public: true
      })

    conn = init_test_session(conn, %{user_id: user.id})

    %{
      conn: conn,
      user: user,
      my_chain: my_chain,
      public_chain: public_chain
    }
  end

  test "shows my and public chains", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chains")

    assert html =~ "My Chains"
    assert html =~ "Public Chains"
    assert html =~ "My Chain"
    assert html =~ "Public Chain"
  end

  test "plays a chain", %{conn: conn, my_chain: my_chain} do
    {:ok, view, _html} = live(conn, "/chains")

    with_mock SoundboardWeb.AudioPlayer, play_chain: fn _chain, _username -> :ok end do
      view
      |> element("[phx-click='play_chain'][phx-value-id='#{my_chain.id}']")
      |> render_click()

      assert_called(SoundboardWeb.AudioPlayer.play_chain(:_, :_))
    end
  end

  test "deletes own chain", %{conn: conn, my_chain: my_chain} do
    {:ok, view, _html} = live(conn, "/chains")

    view
    |> element("[phx-click='delete_chain'][phx-value-id='#{my_chain.id}']")
    |> render_click()

    refute Repo.get(Soundboard.Chains.Chain, my_chain.id)
  end

  defp insert_user(attrs) do
    base = %{
      username: "user#{System.unique_integer()}",
      discord_id: "discord#{System.unique_integer()}"
    }

    {:ok, user} =
      %User{}
      |> User.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    user
  end

  defp insert_sound(user, attrs \\ %{}) do
    base = %{
      filename: "sound#{System.unique_integer()}.mp3",
      source_type: "local",
      user_id: user.id
    }

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    sound
  end
end
