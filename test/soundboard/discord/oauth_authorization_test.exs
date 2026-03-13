defmodule Soundboard.Discord.OAuthAuthorizationTest do
  use ExUnit.Case, async: false

  alias Soundboard.Discord.OAuthAuthorization

  defmodule SuccessMemberClient do
    def get_member_roles(_guild_id, _user_id, _token), do: {:ok, ["role-a", "role-b"]}
  end

  defmodule MemberWithoutRoleClient do
    def get_member_roles(_guild_id, _user_id, _token), do: {:ok, ["guest"]}
  end

  defmodule NotInGuildMemberClient do
    def get_member_roles(_guild_id, _user_id, _token), do: {:error, :not_in_guild}
  end

  setup do
    previous_required_guild_id = Application.get_env(:soundboard, :oauth_required_guild_id)
    previous_allowed_roles = Application.get_env(:soundboard, :oauth_allowed_role_ids)
    previous_member_client = Application.get_env(:soundboard, :discord_member_client)

    Application.put_env(:soundboard, :oauth_required_guild_id, "")
    Application.put_env(:soundboard, :oauth_allowed_role_ids, [])
    Application.put_env(:soundboard, :discord_member_client, Soundboard.Discord.MemberClient)

    on_exit(fn ->
      restore_value(:soundboard, :oauth_required_guild_id, previous_required_guild_id)
      restore_value(:soundboard, :oauth_allowed_role_ids, previous_allowed_roles)
      restore_value(:soundboard, :discord_member_client, previous_member_client)
    end)

    :ok
  end

  test "authorize/2 allows users when no guild requirement is configured" do
    auth = %{uid: "user-1", credentials: %{token: "oauth-token"}}

    assert {:ok, :authorized} = OAuthAuthorization.authorize(auth)
  end

  test "authorize/2 allows users that meet guild and role requirements" do
    Application.put_env(:soundboard, :oauth_required_guild_id, "guild-1")
    Application.put_env(:soundboard, :oauth_allowed_role_ids, ["role-a"])
    Application.put_env(:soundboard, :discord_member_client, SuccessMemberClient)

    auth = %{uid: "user-1", credentials: %{token: "oauth-token"}}

    assert {:ok, :authorized} = OAuthAuthorization.authorize(auth)
  end

  test "authorize/2 denies users missing required roles" do
    Application.put_env(:soundboard, :oauth_required_guild_id, "guild-1")
    Application.put_env(:soundboard, :oauth_allowed_role_ids, ["role-admin"])
    Application.put_env(:soundboard, :discord_member_client, MemberWithoutRoleClient)

    auth = %{uid: "user-1", credentials: %{token: "oauth-token"}}

    assert {:error, :missing_role} = OAuthAuthorization.authorize(auth)
  end

  test "authorize/2 denies users missing from required guild" do
    Application.put_env(:soundboard, :oauth_required_guild_id, "guild-1")
    Application.put_env(:soundboard, :discord_member_client, NotInGuildMemberClient)

    auth = %{uid: "user-1", credentials: %{token: "oauth-token"}}

    assert {:error, :not_in_guild} = OAuthAuthorization.authorize(auth)
  end

  defp restore_value(app, key, nil), do: Application.delete_env(app, key)
  defp restore_value(app, key, value), do: Application.put_env(app, key, value)
end
