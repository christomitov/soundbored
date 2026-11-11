defmodule Soundboard.Credo.OneModulePerFile do
  @moduledoc """
  A file holds one module (the Phoenix skill): modules nested or side by
  side in one file make compile-time dependency cycles, and hide a module
  from anyone looking for its file. Give the second module a file of its
  own, named for it.
  """
  use Credo.Check,
    id: "SB015",
    base_priority: :high,
    category: :design,
    explanations: [check: @moduledoc]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(fn
      {:defmodule, meta, [{:__aliases__, _, name} | _]} = ast, found ->
        {ast, [{meta[:line], name} | found]}

      ast, found ->
        {ast, found}
    end)
    |> Enum.reverse()
    |> Enum.drop(1)
    |> Enum.map(fn {line, name} ->
      format_issue(issue_meta,
        message: "#{Enum.join(name, ".")} is a second module in this file: give it its own.",
        line_no: line
      )
    end)
  end
end
