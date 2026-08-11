defmodule Soundboard.SystemCmdTest do
  use ExUnit.Case, async: true

  alias Soundboard.SystemCmd

  test "run/3 executes commands without timeout option on System.cmd" do
    assert {"hi\n", 0} = SystemCmd.run("echo", ["hi"], stderr_to_stdout: true)
  end

  test "run/3 enforces timeout via Task.yield" do
    assert {"", 124} =
             SystemCmd.run("sleep", ["2"], stderr_to_stdout: true, timeout: 100)
  end
end
