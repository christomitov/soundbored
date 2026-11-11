defmodule Soundboard.Discord.Handler.AutoJoinPolicyTest do
  use ExUnit.Case, async: false

  alias Soundboard.Discord.Handler.AutoJoinPolicy

  setup do
    on_exit(fn -> System.delete_env("AUTO_JOIN") end)
  end

  test "AUTO_JOIN selects the mode, defaulting to play" do
    table = [
      {nil, :play},
      {"play", :play},
      {"presence", :presence},
      {"true", :presence},
      {"TRUE", :presence},
      {"  yes ", :presence},
      {"1", :presence},
      {"false", false},
      {"0", false},
      {"no", false},
      {"unknown", false}
    ]

    for {value, mode} <- table do
      if value, do: System.put_env("AUTO_JOIN", value), else: System.delete_env("AUTO_JOIN")

      assert {value, AutoJoinPolicy.mode()} == {value, mode}
    end
  end
end
