defmodule Soundboard.Credo.FileMatchesModule do
  @moduledoc """
  A module lives where its name says, as Elixir apps lay out `lib/`:
  `Soundboard.Sounds.Upload` is `lib/soundboard/sounds/upload.ex`.
  Phoenix's own folders group files without being part of the name, as its
  generators make them: `live/`, `controllers/` and `components/` in
  `lib/soundboard_web/` (`SoundboardWeb.SoundboardLive` is
  `lib/soundboard_web/live/soundboard_live.ex`), or are part of it when
  the name says so (`SoundboardWeb.Components.Layouts.Navbar` is
  `lib/soundboard_web/components/layouts/navbar.ex`). A module that's
  somewhere else can't be found from its name; move the file, or rename the
  module, so the two agree. Mix tasks (`lib/mix/tasks/`) are named as Mix
  names them.
  """
  use Credo.Check,
    id: "SB016",
    base_priority: :high,
    category: :design,
    explanations: [check: @moduledoc]

  @phoenix_folders ["live", "controllers", "components"]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    case first_module(source_file) do
      nil ->
        []

      {line, name} ->
        expected = path_of(name)

        if expected in comparable(filename),
          do: [],
          else: [
            format_issue(issue_meta,
              message: "#{Enum.join(name, ".")} belongs in #{expected}: move it, or rename it.",
              line_no: line
            )
          ]
    end
  end

  defp first_module(source_file) do
    Credo.Code.prewalk(
      source_file,
      fn
        {:defmodule, meta, [{:__aliases__, _, name} | _]} = ast, nil -> {ast, {meta[:line], name}}
        ast, found -> {ast, found}
      end,
      nil
    )
  end

  @doc "Where a module's file is, from its name: `lib/` and its parts in snake_case."
  def path_of(name),
    do: "lib/" <> Enum.map_join(name, "/", &Macro.underscore(to_string(&1))) <> ".ex"

  # The file's path from `lib/`, as is and with Phoenix's grouping folders taken out.
  defp comparable(filename) do
    case filename |> Path.relative_to_cwd() |> Path.split() do
      ["lib", "soundboard_web" | rest] = parts ->
        [
          Path.join(parts),
          Path.join(["lib", "soundboard_web" | Enum.reject(rest, &(&1 in @phoenix_folders))])
        ]

      parts ->
        [Path.join(parts)]
    end
  end
end
