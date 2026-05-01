defmodule Soundboard.Discord.RoleCheckerTest do
  use ExUnit.Case, async: false

  import Mock

  alias EDA.API.Member
  alias Soundboard.Discord.RoleChecker

  setup do
    previous_guild = Application.get_env(:soundboard, :required_guild_id)
    previous_roles = Application.get_env(:soundboard, :required_role_ids)

    on_exit(fn ->
      restore_env(:required_guild_id, previous_guild)
      restore_env(:required_role_ids, previous_roles || [])
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:soundboard, key)
  defp restore_env(key, value), do: Application.put_env(:soundboard, key, value)

  describe "feature_enabled?/0" do
    test "returns false when guild_id is missing" do
      Application.put_env(:soundboard, :required_guild_id, nil)
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      refute RoleChecker.feature_enabled?()
    end

    test "returns false when role_ids is empty" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, [])

      refute RoleChecker.feature_enabled?()
    end

    test "returns true when both guild_id and role_ids are configured" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      assert RoleChecker.feature_enabled?()
    end
  end

  describe "authorized?/1" do
    test "returns true when feature is disabled and does not call the API" do
      Application.put_env(:soundboard, :required_guild_id, nil)
      Application.put_env(:soundboard, :required_role_ids, [])

      with_mock Member, get: fn _, _ -> flunk("API should not be called when disabled") end do
        assert RoleChecker.authorized?("user1")
      end
    end

    test "returns true when member has at least one required role" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1", "r2"])

      with_mock Member,
        get: fn "g1", "user1" -> {:ok, %{"roles" => ["other", "r2"]}} end do
        assert RoleChecker.authorized?("user1")
        assert_called(Member.get("g1", "user1"))
      end
    end

    test "returns false when member has none of the required roles" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      with_mock Member,
        get: fn "g1", "user1" -> {:ok, %{"roles" => ["other_role"]}} end do
        refute RoleChecker.authorized?("user1")
      end
    end

    test "returns false when API returns an error" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      with_mock Member, get: fn _, _ -> {:error, :not_found} end do
        refute RoleChecker.authorized?("user1")
      end
    end

    test "returns false when API response shape is unexpected" do
      Application.put_env(:soundboard, :required_guild_id, "g1")
      Application.put_env(:soundboard, :required_role_ids, ["r1"])

      with_mock Member, get: fn _, _ -> {:ok, %{"unexpected" => "shape"}} end do
        refute RoleChecker.authorized?("user1")
      end
    end
  end
end
