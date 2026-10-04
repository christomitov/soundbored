defmodule Soundboard.Discord.InviteURLTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Soundboard.Discord.InviteURL

  test "permission integer is pinned to view channel, connect, speak" do
    expected = 1 <<< 10 ||| 1 <<< 20 ||| 1 <<< 3
    assert InviteURL.permissions() == expected
    assert InviteURL.permissions() == 1_049_608
  end

  test "build embeds the client id, scope, and permissions" do
    url = InviteURL.build("1234567890")

    assert url ==
             "https://discord.com/oauth2/authorize?client_id=1234567890" <>
               "&permissions=1049608&scope=bot%20applications.commands"
  end
end
