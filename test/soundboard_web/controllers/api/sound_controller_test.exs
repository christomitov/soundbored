defmodule SoundboardWeb.API.SoundControllerTest do
  @moduledoc """
  Test for the SoundController.
  """
  use SoundboardWeb.ConnCase
  alias Soundboard.Accounts.User
  alias Soundboard.{Repo, Sound, Tag}
  import Mock

  setup %{conn: conn} do
    # Set test API token in environment
    System.put_env("API_TOKEN", "test-token")
    on_exit(fn -> System.delete_env("API_TOKEN") end)

    user = insert_user()
    sound = insert_sound(user)
    tag = insert_tag()

    # Add tag to sound
    insert_sound_tag(sound, tag)

    conn =
      conn
      |> put_req_header("authorization", "Bearer test-token")

    %{conn: conn, sound: sound, user: user}
  end

  describe "index" do
    test "lists all sounds with their tags", %{conn: conn} do
      conn = get(conn, ~p"/api/sounds")
      assert %{"data" => sounds} = json_response(conn, 200)

      # Verify response structure for each sound
      Enum.each(sounds, fn sound_data ->
        assert is_integer(sound_data["id"])
        assert is_binary(sound_data["filename"])
        assert is_list(sound_data["tags"])
        assert sound_data["inserted_at"]
        assert sound_data["updated_at"]
      end)
    end

    test "returns sounds in expected format", %{conn: conn, sound: sound} do
      conn = get(conn, ~p"/api/sounds")
      assert %{"data" => sounds} = json_response(conn, 200)

      # Find our test sound in the results
      test_sound = Enum.find(sounds, &(&1["id"] == sound.id))
      assert test_sound
      assert test_sound["filename"] == sound.filename
      assert is_list(test_sound["tags"])
    end
  end

  describe "play" do
    test "plays a sound successfully", %{conn: conn, sound: sound} do
      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _filename, _username -> :ok end do
        conn =
          conn
          |> put_req_header("x-username", "TestUser")
          |> post(~p"/api/sounds/#{sound.id}/play")

        assert %{
                 "status" => "success",
                 "message" => "Playing sound: " <> _,
                 "played_by" => "TestUser"
               } = json_response(conn, 200)
      end
    end

    test "plays a sound with default username when x-username not provided", %{
      conn: conn,
      sound: sound
    } do
      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _filename, _username -> :ok end do
        conn = post(conn, ~p"/api/sounds/#{sound.id}/play")

        assert %{
                 "status" => "success",
                 "message" => "Playing sound: " <> _,
                 "played_by" => "API User"
               } = json_response(conn, 200)
      end
    end

    test "returns error when sound not found", %{conn: conn} do
      with_mock SoundboardWeb.AudioPlayer, play_sound: fn _filename, _username -> :ok end do
        conn = post(conn, ~p"/api/sounds/999999/play")
        assert %{"error" => "Sound not found"} = json_response(conn, 404)
      end
    end

    test "returns unauthorized without valid API token" do
      conn = build_conn()
      conn = post(conn, ~p"/api/sounds/1/play")
      assert json_response(conn, 401)
    end
  end

  # Helper functions
  defp insert_sound(user) do
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "test_sound#{System.unique_integer([:positive])}.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert()

    sound
  end

  defp insert_tag do
    {:ok, tag} =
      %Tag{}
      |> Tag.changeset(%{name: "test_tag#{System.unique_integer([:positive])}"})
      |> Repo.insert()

    tag
  end

  defp insert_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "testuser#{System.unique_integer([:positive])}",
        discord_id: "#{System.unique_integer([:positive])}",
        avatar: "test_avatar.jpg"
      })
      |> Repo.insert()

    user
  end

  defp insert_sound_tag(sound, tag) do
    {:ok, _} =
      %Soundboard.SoundTag{}
      |> Soundboard.SoundTag.changeset(%{
        sound_id: sound.id,
        tag_id: tag.id
      })
      |> Repo.insert()
  end
end
