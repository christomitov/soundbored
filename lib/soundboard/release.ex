defmodule Soundboard.Release do
  @moduledoc false

  @app :soundboard

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo_ref ->
          Ecto.Migrator.run(repo_ref, :up, all: true)
        end)
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn repo_ref ->
        Ecto.Migrator.run(repo_ref, :down, to: version)
      end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
