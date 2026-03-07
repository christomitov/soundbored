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

  test "mode/0 is always enabled in test" do
    Application.put_env(:soundboard, :env, :test)
    System.put_env("AUTO_JOIN", "false")

    assert AutoJoinPolicy.mode() == :enabled
  end

  test "enabled?/0 recognizes truthy AUTO_JOIN values" do
    Application.put_env(:soundboard, :env, :dev)

    for value <- ["true", "TRUE", "  yes ", "1"] do
      System.put_env("AUTO_JOIN", value)
      assert AutoJoinPolicy.enabled?()
      assert AutoJoinPolicy.mode() == :enabled
    end
  end

  test "enabled?/0 returns false for missing or non-truthy values" do
    Application.put_env(:soundboard, :env, :dev)

    System.delete_env("AUTO_JOIN")
    refute AutoJoinPolicy.enabled?()
    assert AutoJoinPolicy.mode() == :disabled

    for value <- ["false", "0", "no", "later"] do
      System.put_env("AUTO_JOIN", value)
      refute AutoJoinPolicy.enabled?()
      assert AutoJoinPolicy.mode() == :disabled
    end
  end
end
