defmodule Soundboard.Credo.MigrationCarriesData do
  @moduledoc """
  A schema change doesn't move data: moving a column (to another table,
  or into its own records) as an `add` there and a `remove` here drops
  the values in it; a new
  `NOT NULL` column on a table with rows fails to migrate. So a migration
  whose `up` (or `change`), inside `alter table` (of a table it didn't
  just create), removes a column, or adds or modifies one to
  `null: false` without a default, carries its data:

    * an `execute` step copying or backfilling it, between the schema
      steps (and `down` copying it back); or
    * a `# no data to carry: <why>` comment, when there's truly nothing to
      keep (a column nothing ever wrote to, a table that's always empty).

  Migrations older than `since` (a migration timestamp) are left as they
  ran.
  """
  use Credo.Check,
    id: "SB006",
    base_priority: :high,
    category: :warning,
    param_defaults: [since: 20_261_110_000_000],
    explanations: [
      check: @moduledoc,
      params: [since: "The oldest migration timestamp checked (older ones already ran)."]
    ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    with "priv/repo/migrations/" <> name <- relative(filename),
         {timestamp, "_" <> _} <- Integer.parse(name),
         true <- timestamp >= Params.get(params, :since, __MODULE__),
         source = SourceFile.source(source_file),
         false <- String.contains?(source, "# no data to carry:"),
         {:ok, ast} <- Code.string_to_quoted(source),
         false <- executes?(ast) do
      issue_meta = IssueMeta.for(source_file, params)

      ast
      |> forward_steps()
      |> Enum.flat_map(&dropping/1)
      |> Enum.map(fn {what, line} -> issue(what, line, issue_meta) end)
    else
      _ -> []
    end
  end

  defp relative(filename), do: Path.relative_to_cwd(filename)

  defp executes?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:execute, _, [_ | _]} = node, _found? -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  # The bodies of `up/0` and `change/0`, where the schema moves forward.
  defp forward_steps(ast) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{name, _, _}, [do: body]]} = node, bodies when name in [:up, :change] ->
          {node, [body | bodies]}

        node, bodies ->
          {node, bodies}
      end)

    bodies
  end

  # What, inside an `alter table`, needs data carried; a table this same
  # migration creates has no rows.
  defp dropping(body) do
    {_ast, {_created, found}} =
      Macro.prewalk(body, {MapSet.new(), []}, fn
        {:create, _, [{:table, _, [name | _]} | _]} = node, {created, found} ->
          {node, {MapSet.put(created, name), found}}

        {:alter, _, [{:table, _, [name | _]}, [do: block]]} = node, {created, found} ->
          if name in created,
            do: {node, {created, found}},
            else: {node, {created, found ++ in_alter(block)}}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp in_alter(block) do
    {_ast, found} =
      Macro.prewalk(block, [], fn
        {:remove, meta, [column | _]} = node, found ->
          {node, [{"removes #{Macro.to_string(column)}", meta[:line]} | found]}

        {call, meta, [column, _type, opts]} = node, found
        when call in [:add, :modify] and is_list(opts) ->
          if opts[:null] == false and not Keyword.has_key?(opts, :default),
            do: {node, [{"makes #{Macro.to_string(column)} NOT NULL", meta[:line]} | found]},
            else: {node, found}

        node, found ->
          {node, found}
      end)

    Enum.reverse(found)
  end

  defp issue(what, line, issue_meta),
    do:
      format_issue(issue_meta,
        message:
          "This migration #{what} without carrying its data: add an `execute` copying or " <>
            "backfilling it, or a `# no data to carry: <why>` comment.",
        trigger: what,
        line_no: line
      )
end
