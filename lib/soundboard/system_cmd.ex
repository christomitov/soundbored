defmodule Soundboard.SystemCmd do
  @moduledoc false

  @spec configured_executable(atom(), String.t()) :: String.t() | nil
  def configured_executable(config_key, system_name)
      when is_atom(config_key) and is_binary(system_name) do
    case Application.get_env(:soundboard, config_key, :system) do
      :system -> System.find_executable(system_name)
      false -> nil
      path when is_binary(path) -> path
    end
  end

  @doc """
  Runs `System.cmd/3` with an optional wall-clock timeout.

  Elixir's `System.cmd/3` does not accept `:timeout` in all releases, so we
  enforce timeouts via `Task.yield/2` instead.
  """
  @spec run(String.t(), [String.t()], keyword()) ::
          {Collectable.t(), exit_status :: non_neg_integer()}
  def run(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    {timeout, cmd_opts} = Keyword.pop(opts, :timeout, :infinity)

    case timeout do
      :infinity ->
        System.cmd(command, args, cmd_opts)

      ms when is_integer(ms) and ms > 0 ->
        task = Task.async(fn -> System.cmd(command, args, cmd_opts) end)

        case Task.yield(task, ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, result} ->
            result

          nil ->
            {"", 124}
        end
    end
  end
end
