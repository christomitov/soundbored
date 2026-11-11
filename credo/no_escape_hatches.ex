defmodule Soundboard.Credo.NoEscapeHatches do
  @moduledoc """
  A check switched off for a line (`credo:disable`) or a warning silenced
  (`@dialyzer nowarn`) is a rule the code no longer has to pass. Fix the
  code; if a rule is wrong, say so and change the rule — not the code.
  """
  use Credo.Check,
    id: "SB008",
    base_priority: :high,
    category: :design,
    explanations: [check: @moduledoc]

  @escapes [
    {~r/credo:disable/, "credo:disable"},
    {~r/@dialyzer/, "@dialyzer"}
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    for {line, text} <- Credo.Code.to_lines(source_file),
        {regex, name} <- @escapes,
        Regex.match?(regex, text) do
      format_issue(issue_meta,
        message: "`#{name}` silences a rule: fix the code, or ask a human to change the rule.",
        trigger: name,
        line_no: line
      )
    end
  end
end
