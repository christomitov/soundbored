defmodule Soundboard.ReleaseTest do
  use ExUnit.Case, async: true
  import Mock

  test "migrate runs up migrations for configured repos" do
    original_repos = Application.get_env(:soundboard, :ecto_repos)
    Application.put_env(:soundboard, :ecto_repos, [:fake_repo])

    on_exit(fn ->
      Application.put_env(:soundboard, :ecto_repos, original_repos)
    end)

    with_mock Ecto.Migrator,
      with_repo: fn repo, fun ->
        assert repo == :fake_repo
        {:ok, repo, fun.(repo)}
      end,
      run: fn repo, direction, opts ->
        assert repo == :fake_repo
        assert direction == :up
        assert opts == [all: true]
        {:ok, :ran_up}
      end do
      assert Soundboard.Release.migrate() == [{:ok, :fake_repo, {:ok, :ran_up}}]
      assert_called(Ecto.Migrator.run(:fake_repo, :up, all: true))
    end
  end

  test "rollback runs down migrations to a specific version" do
    original_repos = Application.get_env(:soundboard, :ecto_repos)
    Application.put_env(:soundboard, :ecto_repos, [:fake_repo])

    on_exit(fn ->
      Application.put_env(:soundboard, :ecto_repos, original_repos)
    end)

    with_mock Ecto.Migrator,
      with_repo: fn repo, fun -> {:ok, repo, fun.(repo)} end,
      run: fn repo, direction, opts ->
        assert repo == :fake_repo
        assert direction == :down
        assert opts == [to: 123]
        {:ok, :ran_down}
      end do
      assert {:ok, :fake_repo, {:ok, :ran_down}} = Soundboard.Release.rollback(:fake_repo, 123)
      assert_called(Ecto.Migrator.run(:fake_repo, :down, to: 123))
    end
  end
end
