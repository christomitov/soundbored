defmodule Soundboard.Discord.InviteTest do
  use ExUnit.Case, async: false

  import Mock

  alias Soundboard.Discord.{GuildCache, Invite}

  setup do
    previous =
      Application.get_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth)

    Application.put_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth,
      client_id: "123456789012345678"
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth, previous)
      else
        Application.delete_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth)
      end
    end)

    :ok
  end

  test "url/0 builds a Discord bot invite URL with required permissions" do
    url = Invite.url()

    assert url =~ "https://discord.com/api/oauth2/authorize?"
    assert url =~ "client_id=123456789012345678"
    assert url =~ "permissions=3214336"
    assert url =~ "scope=bot"
  end

  test "url/0 returns nil when client id is missing" do
    Application.put_env(:ueberauth, Ueberauth.Strategy.Discord.OAuth, client_id: nil)
    assert Invite.url() == nil
  end

  test "in_guild?/0 is true when guild cache has entries" do
    with_mock GuildCache, all: fn -> [%{id: "1", name: "Test"}] end do
      assert Invite.in_guild?()
    end
  end

  test "in_guild?/0 is false when guild cache is empty or unavailable" do
    with_mock GuildCache, all: fn -> [] end do
      refute Invite.in_guild?()
    end

    with_mock GuildCache, all: fn -> raise "cache unavailable" end do
      refute Invite.in_guild?()
    end
  end
end
