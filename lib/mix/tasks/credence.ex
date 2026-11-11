if Code.ensure_loaded?(Credence) do
  defmodule Mix.Tasks.Credence do
    @shortdoc "Rewrites lib/ and test/ the Elixir way (Credence); --check fails instead"
    @moduledoc """
    Credence finds code that works but isn't written the Elixir way (a list
    built only to be summed, a zip then a map) and rewrites it.
    `mix credence` fixes each file it finds something in, in place, with
    `Credence.fix/2`, and lists what it couldn't fix; `mix credence --check`
    (precommit and CI) changes nothing and fails listing what it finds.

    Only the rules that hold for any Unicode text run (`config :credence,
    assumptions: :strict`, in dev and test): sound names and tags aren't
    plain ASCII.
    """
    use Mix.Task

    @impl true
    def run(args) do
      Mix.Task.run("compile")

      found =
        for path <- Path.wildcard("{lib,test}/**/*.{ex,exs}"),
            issues = issues(path),
            do: {path, issues}

      case {args, found} do
        {_args, []} ->
          :ok

        {["--check"], found} ->
          Mix.raise("Credence found these; `mix credence` fixes them:\n" <> listed(found))

        {_args, found} ->
          fix(found)
      end
    end

    defp issues(path) do
      case Credence.Pattern.analyze(File.read!(path)) do
        [] -> nil
        issues -> issues
      end
    end

    defp fix(found) do
      left =
        for {path, _issues} <- found,
            %{issues: [_ | _] = issues} <- [fixed(path)],
            do: {path, issues}

      if left != [],
        do: Mix.raise("Credence couldn't fix these; fix them by hand:\n" <> listed(left))
    end

    defp fixed(path) do
      %{code: code} = result = Credence.fix(File.read!(path))
      File.write!(path, code)
      Mix.shell().info("Fixed #{path}")
      result
    end

    defp listed(found) do
      Enum.map_join(found, "\n", fn {path, issues} ->
        Enum.map_join(issues, "\n", &"  #{path}:#{&1.meta[:line]} #{&1.message}")
      end)
    end
  end
end
