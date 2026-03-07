defmodule Soundboard.AccountsTest do
  use Soundboard.DataCase

  alias Soundboard.Accounts
  alias Soundboard.Accounts.User
  alias Soundboard.Repo

  test "get_user/1 returns the persisted user" do
    user =
      %User{}
      |> User.changeset(%{
        username: "accounts_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert!()

    user_id = user.id
    assert %User{id: ^user_id} = Accounts.get_user(user.id)
  end

  test "get_user/1 returns nil for missing users" do
    assert Accounts.get_user(-1) == nil
  end

  test "avatars_by_usernames/1 returns avatars keyed by username" do
    user =
      %User{}
      |> User.changeset(%{
        username: "avatars_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar-keyed.png"
      })
      |> Repo.insert!()

    assert Accounts.avatars_by_usernames([]) == %{}

    assert Accounts.avatars_by_usernames([user.username, "missing"]) == %{
             user.username => "avatar-keyed.png"
           }
  end
end
