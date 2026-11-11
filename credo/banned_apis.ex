defmodule Soundboard.Credo.BannedApis do
  @moduledoc """
  What AGENTS.md and the Phoenix skill say not to reach for, each with what
  to use instead:

    * `Heroicons.*` modules: `<.icon name="hero-...">`;
    * HTTPoison, Tesla, `:httpc`: `Req`;
    * `Phoenix.View`, `~E`, `form_for`: Phoenix 1.8's function components,
      `~H` and `<.form for={...}>`;
    * `live_redirect`, `live_patch`: `<.link navigate/patch>`, `push_navigate`,
      `push_patch`;
    * a whole process dictionary (`Process.info(pid, :dictionary)`,
      `Process.get/0`): the one key, `{:dictionary, key}` or `Process.get(key)`.
      Copying every process's dictionary once took a test run to 58 GB.
  """
  use Credo.Check,
    id: "SB013",
    base_priority: :high,
    category: :warning,
    explanations: [check: @moduledoc]

  @modules %{
    [:Heroicons] => "<.icon name=\"hero-...\">",
    [:HTTPoison] => "Req",
    [:Tesla] => "Req",
    [:Phoenix, :View] => "function components"
  }
  @functions %{
    form_for: "<.form for={...}>",
    live_redirect: "<.link navigate> or push_navigate",
    live_patch: "<.link patch> or push_patch"
  }

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:__aliases__, meta, modules} = ast, issues, issue_meta) do
    case Enum.find(@modules, fn {banned, _} -> List.starts_with?(modules, banned) end) do
      {banned, instead} ->
        {ast, [issue(issue_meta, meta, Enum.join(banned, "."), instead) | issues]}

      nil ->
        {ast, issues}
    end
  end

  defp traverse({{:., meta, [:httpc, _call]}, _, _} = ast, issues, issue_meta),
    do: {ast, [issue(issue_meta, meta, ":httpc", "Req") | issues]}

  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Process]}, :info]}, _, [_pid, :dictionary]} = ast,
         issues,
         issue_meta
       ),
       do:
         {ast,
          [
            issue(issue_meta, meta, "Process.info(pid, :dictionary)", "{:dictionary, key}")
            | issues
          ]}

  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Process]}, :get]}, _, []} = ast,
         issues,
         issue_meta
       ),
       do: {ast, [issue(issue_meta, meta, "Process.get()", "Process.get(key)") | issues]}

  defp traverse({name, meta, args} = ast, issues, issue_meta)
       when is_map_key(@functions, name) and is_list(args),
       do: {ast, [issue(issue_meta, meta, to_string(name), @functions[name]) | issues]}

  defp traverse({:sigil_E, meta, _} = ast, issues, issue_meta),
    do: {ast, [issue(issue_meta, meta, "~E", "~H") | issues]}

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue(issue_meta, meta, what, instead) do
    format_issue(issue_meta,
      message: "#{what}: use #{instead}.",
      trigger: what,
      line_no: meta[:line]
    )
  end
end
