defmodule Soundboard.Credo.NoComments do
  @moduledoc """
  The code is the record of how the system is now. Code carries no
  comments: names say what things are (`<%!-- --%>` in a template is
  it is HEEx, not Elixir). A `@moduledoc` or `@doc` says what the
  thing is today, so it cites no issue (`#123`) or Sentry event: that's
  history, kept in git and the issues.
  """
  use Credo.Check,
    id: "SB021",
    base_priority: :high,
    category: :readability,
    explanations: [check: @moduledoc]

  @history ~r/(?<![\w&\/])#\d{2,}\b|Sentry/

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    case Code.string_to_quoted_with_comments(SourceFile.source(source_file)) do
      {:ok, quoted, comments} ->
        Enum.map(comments, &issue(issue_meta, &1.line, "A comment: let the names say it.")) ++
          history(quoted, issue_meta)

      {:error, _unparsable} ->
        []
    end
  end

  defp history(quoted, issue_meta) do
    quoted
    |> Macro.prewalk([], fn
      {:@, meta, [{doc, _, [text]}]} = node, found
      when doc in [:moduledoc, :doc] and is_binary(text) ->
        {node, if(text =~ @history, do: [meta[:line] | found], else: found)}

      node, found ->
        {node, found}
    end)
    |> elem(1)
    |> Enum.map(
      &issue(
        issue_meta,
        &1,
        "A doc citing an issue or Sentry: say what it is now; history is in git."
      )
    )
  end

  defp issue(issue_meta, line, message),
    do: format_issue(issue_meta, message: message, line_no: line)
end
