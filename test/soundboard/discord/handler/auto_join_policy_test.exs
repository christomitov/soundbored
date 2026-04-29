defmodule Soundboard.Discord.Handler.AutoJoinPolicyTest do
  use ExUnit.Case, async: false

  alias Soundboard.Discord.Handler.AutoJoinPolicy

  setup do
    original_env = Application.get_env(:soundboard, :env)
    original_auto_join = System.get_env("AUTO_JOIN")

    on_exit(fn ->
      Application.put_env(:soundboard, :env, original_env)

      if is_nil(original_auto_join) do
        System.delete_env("AUTO_JOIN")
      else
        System.put_env("AUTO_JOIN", original_auto_join)
      end
    end)

    :ok
  end

  test "mode/0 is :play in test environment regardless of AUTO_JOIN" do
    Application.put_env(:soundboard, :env, :test)
    System.put_env("AUTO_JOIN", "false")
    assert AutoJoinPolicy.mode() == :play
  end

  test "defaults to :play when AUTO_JOIN is not set" do
    Application.put_env(:soundboard, :env, :dev)
    System.delete_env("AUTO_JOIN")
    assert AutoJoinPolicy.mode() == :play
  end

  test "AUTO_JOIN=play returns :play" do
    Application.put_env(:soundboard, :env, :dev)
    System.put_env("AUTO_JOIN", "play")
    assert AutoJoinPolicy.mode() == :play
  end

  test "AUTO_JOIN=presence returns :presence" do
    Application.put_env(:soundboard, :env, :dev)
    System.put_env("AUTO_JOIN", "presence")
    assert AutoJoinPolicy.mode() == :presence
  end

  test "truthy values map to :presence" do
    Application.put_env(:soundboard, :env, :dev)

    for value <- ["true", "TRUE", "  yes ", "1"] do
      System.put_env("AUTO_JOIN", value)
      assert AutoJoinPolicy.mode() == :presence
    end
  end

  test "falsy and unknown values map to false" do
    Application.put_env(:soundboard, :env, :dev)

    for value <- ["false", "0", "no", "never", "unknown"] do
      System.put_env("AUTO_JOIN", value)
      assert AutoJoinPolicy.mode() == false
    end
  end
end
