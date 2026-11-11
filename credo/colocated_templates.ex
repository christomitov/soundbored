defmodule Soundboard.Credo.ColocatedTemplates do
  @moduledoc """
  Markup lives in `.html.heex` files, as Phoenix does it, never in a `~H`
  heredoc: real HEEx for the editor and the formatter, the module holding
  only the logic. A LiveView or LiveComponent renders from its template
  beside it (`index.ex` and `index.html.heex`); a module's function
  components are templates in a folder named for it (`embed_templates
  "form/*"`, `form/category_picker.html.heex`), each named for the
  component. What a component works out, its template asks a function for
  (`{more(@events)}`); a component with several shapes is one template, or
  hands each shape to a component named for it (`checkbox_input`), never a
  second template for the same thing (`<name>_markup`). A one-line `~H"..."`
  is fine.
  """
  use Credo.Check,
    id: "SB017",
    base_priority: :high,
    category: :design,
    explanations: [check: @moduledoc]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.source()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, no} -> problems(line, no, issue_meta) end)
  end

  defp problems(line, no, issue_meta) do
    cond do
      String.contains?(line, ~S(~H""")) ->
        [
          format_issue(issue_meta,
            message:
              "A ~H heredoc: put the markup in a .html.heex file (colocated, or embed_templates).",
            line_no: no
          )
        ]

      Regex.match?(~r/\b\w+_markup\(/, line) ->
        [
          format_issue(issue_meta,
            message:
              "A <name>_markup template: name the template for its component, and have it call functions for what it works out.",
            line_no: no
          )
        ]

      true ->
        []
    end
  end
end
