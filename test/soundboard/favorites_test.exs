defmodule Soundboard.FavoritesTest do
  @moduledoc """
  Test for the Favorites module.
  """
  use Soundboard.DataCase
  alias Soundboard.{Accounts.User, Favorites, Sound}
  alias Soundboard.Accounts.Tenants

  describe "favorites" do
    setup do
      user = insert_user()
      sound = insert_sound(user)
      %{user: user, sound: sound}
    end

    test "list_favorites/1 returns all favorites for a user", %{user: user, sound: sound} do
      {:ok, _favorite} = Favorites.toggle_favorite(user.id, sound.id)
      assert [sound.id] == Favorites.list_favorites(user.id)
    end

    test "toggle_favorite/2 adds a favorite when it doesn't exist", %{user: user, sound: sound} do
      assert {:ok, favorite} = Favorites.toggle_favorite(user.id, sound.id)
      assert favorite.user_id == user.id
      assert favorite.sound_id == sound.id
    end

    test "toggle_favorite/2 removes a favorite when it exists", %{user: user, sound: sound} do
      {:ok, _favorite} = Favorites.toggle_favorite(user.id, sound.id)
      {:ok, deleted_favorite} = Favorites.toggle_favorite(user.id, sound.id)
      assert deleted_favorite.__meta__.state == :deleted
      assert [] == Favorites.list_favorites(user.id)
    end

    test "favorite?/2 returns true when favorite exists", %{user: user, sound: sound} do
      refute Favorites.favorite?(user.id, sound.id)
      {:ok, _favorite} = Favorites.toggle_favorite(user.id, sound.id)
      assert Favorites.favorite?(user.id, sound.id)
    end

    test "max_favorites/0 returns the maximum number of favorites allowed" do
      assert Favorites.max_favorites() == 16
    end

    test "cannot add more favorites than max_favorites", %{user: user} do
      # Create max_favorites + 1 number of sounds
      sounds = Enum.map(1..(Favorites.max_favorites() + 1), fn _ -> insert_sound(user) end)

      # Add max_favorites successfully
      Enum.each(Enum.take(sounds, Favorites.max_favorites()), fn sound ->
        assert {:ok, _} = Favorites.toggle_favorite(user.id, sound.id)
      end)

      # Try to add one more favorite - should fail
      last_sound = List.last(sounds)

      assert {:error, "You can only have 16 favorites"} =
               Favorites.toggle_favorite(user.id, last_sound.id)
    end
  end

  # Helper functions
  defp insert_user(attrs \\ %{}) do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(
        Map.merge(
          %{
            username: "testuser",
            discord_id: "123456789",
            avatar: "test_avatar.jpg",
            tenant_id: tenant.id
          },
          attrs
        )
      )
      |> Repo.insert()

    user
  end

  defp insert_sound(user, attrs \\ %{}) do
    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(
        Map.merge(
          %{
            filename: "test_sound#{System.unique_integer()}.mp3",
            source_type: "local",
            user_id: user.id
          },
          attrs
        )
      )
      |> Repo.insert()

    sound
  end
end
