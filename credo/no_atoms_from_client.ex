defmodule Soundboard.Credo.NoAtomsFromClient do
  @moduledoc """
  The web layer never makes atoms from strings. What it gets (event and
  form params) is the client's to send: `String.to_atom/1` grows the atom
  table forever, and `String.to_existing_atom/1` crashes the LiveView on
  any value the page didn't offer.

  Pass the string to an Ecto changeset instead (an `Ecto.Enum` field
  casts it and rejects what isn't in `values`), or look it up in what the
  page offers: `@views %{"grid" => :grid, "list" => :list}`,
  matched with `when is_map_key(@views, view)`.
  """
  use Credo.Check,
    id: "SB005",
    base_priority: :high,
    category: :warning,
    param_defaults: [paths: ["lib/soundboard_web/"]],
    explanations: [
      check: @moduledoc,
      params: [paths: "Paths (prefixes) the check applies to."]
    ]

  @banned [:to_atom, :to_existing_atom]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if Enum.any?(Params.get(params, :paths, __MODULE__), &String.contains?(filename, &1)) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp traverse({{:., meta, [{:__aliases__, _, [:String]}, fun]}, _, _} = ast, issues, issue_meta)
       when fun in @banned do
    issue =
      format_issue(issue_meta,
        message:
          "String.#{fun} on what the client sent: cast it with Ecto.Enum, or look it up in the choices offered.",
        trigger: "String.#{fun}",
        line_no: meta[:line]
      )

    {ast, [issue | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}
end
