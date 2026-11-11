defmodule Soundboard.Credo.NoPhxValueValue do
  @moduledoc """
  `phx-value-value` never reaches the server: LiveView sends a clicked
  element's own `value` property under the same key, and for a button or a
  link without one that is "", which wins. Give a button `value={...}`
  (it is sent as `"value"`), or name the param something else
  (`phx-value-option`).
  """
  use Credo.Check,
    id: "SB003",
    base_priority: :high,
    category: :warning,
    explanations: [check: @moduledoc]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.lines()
    |> Enum.filter(fn {_line_no, line} -> String.contains?(line, "phx-value-value") end)
    |> Enum.map(fn {line_no, _line} ->
      format_issue(issue_meta,
        message:
          "phx-value-value arrives as \"\": use the button's own value={...}, or another name.",
        trigger: "phx-value-value",
        line_no: line_no
      )
    end)
  end
end
