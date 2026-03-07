defmodule Soundboard.Discord.BotIdentityTest do
  use ExUnit.Case, async: false

  import Mock

  alias EDA.API.User, as: APIUser
  alias EDA.Cache
  alias Soundboard.Discord.BotIdentity

  test "fetch/0 returns normalized cached user when available" do
    with_mocks([
      {Cache, [], [me: fn -> %{"id" => "cached-user"} end]},
      {APIUser, [], [me: fn -> flunk("API should not be called when cache is warm") end]}
    ]) do
      assert {:ok, %{id: "cached-user"}} = BotIdentity.fetch()
    end
  end

  test "fetch/0 retrieves from the API and caches the user on cache miss" do
    test_pid = self()
    fetched_user = %{id: "api-user"}

    with_mocks([
      {Cache, [],
       [
         me: fn -> nil end,
         put_me: fn ^fetched_user ->
           send(test_pid, :cached_user)
           :ok
         end
       ]},
      {APIUser, [], [me: fn -> {:ok, fetched_user} end]}
    ]) do
      assert {:ok, %{id: "api-user"}} = BotIdentity.fetch()
      assert_receive :cached_user
      assert_called(APIUser.me())
      assert_called(Cache.put_me(fetched_user))
    end
  end

  test "fetch/0 returns non-success API responses unchanged" do
    with_mocks([
      {Cache, [], [me: fn -> nil end, put_me: fn _ -> :ok end]},
      {APIUser, [], [me: fn -> {:error, :unavailable} end]}
    ]) do
      assert {:error, :unavailable} = BotIdentity.fetch()
    end
  end
end
