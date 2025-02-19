defmodule Soundboard.Tags.TagTest do
  use Soundboard.DataCase
  alias Soundboard.{Tag, Sound, Repo}
  import Ecto.Changeset

  describe "tag validation" do
    test "requires name" do
      changeset = Tag.changeset(%Tag{}, %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces unique names" do
      {:ok, _tag} =
        %Tag{name: "test"}
        |> Tag.changeset(%{})
        |> unique_constraint(:name)
        |> Repo.insert()

      {:error, changeset} =
        %Tag{name: "test"}
        |> Tag.changeset(%{})
        |> unique_constraint(:name)
        |> Repo.insert()

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "tag management" do
    setup do
      user = insert_user()
      {:ok, sound} = insert_sound(user)
      {:ok, tag} = %Tag{name: "test_tag"} |> Tag.changeset(%{}) |> Repo.insert()
      %{sound: sound, tag: tag}
    end

    test "associates tags with sounds", %{sound: sound, tag: tag} do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      # Insert directly into join table with timestamps
      Repo.query!(
        "INSERT INTO sound_tags (sound_id, tag_id, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        [sound.id, tag.id, now, now]
      )

      updated_sound = Repo.preload(sound, :tags)
      assert [%{name: "test_tag"}] = updated_sound.tags
    end
  end

  describe "tag search" do
    setup do
      {:ok, _} = Repo.insert(%Tag{name: "test"})
      {:ok, _} = Repo.insert(%Tag{name: "testing"})
      {:ok, _} = Repo.insert(%Tag{name: "other"})
      :ok
    end

    test "finds tags by partial name match" do
      results = Tag.search("test") |> Repo.all()
      assert length(results) == 2
      assert Enum.map(results, & &1.name) |> Enum.sort() == ["test", "testing"]
    end

    test "search is case insensitive" do
      results = Tag.search("TEST") |> Repo.all()
      assert length(results) == 2
      assert Enum.map(results, & &1.name) |> Enum.sort() == ["test", "testing"]
    end
  end

  # Helper functions
  defp insert_user do
    {:ok, user} =
      %Soundboard.Accounts.User{}
      |> Soundboard.Accounts.User.changeset(%{
        username: "test_user",
        discord_id: "123456",
        avatar: "test.jpg"
      })
      |> Repo.insert()

    user
  end

  defp insert_sound(user) do
    %Sound{}
    |> Sound.changeset(%{
      filename: "test_sound.mp3",
      source_type: "local",
      user_id: user.id
    })
    |> Repo.insert()
  end
end
