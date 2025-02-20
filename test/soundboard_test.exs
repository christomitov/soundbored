defmodule SoundboardTest do
  use ExUnit.Case, async: true
  doctest Soundboard

  describe "module documentation" do
    test "module exists" do
      assert {:module, Soundboard} == Code.ensure_loaded(Soundboard)
      assert function_exported?(Soundboard, :__info__, 1)
    end

    test "has module documentation" do
      moduledoc = Code.fetch_docs(Soundboard)
      assert match?({:docs_v1, _, :elixir, _, %{"en" => _}, _, _}, moduledoc)

      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} = moduledoc
      assert doc =~ "Soundboard keeps the contexts"
      assert doc =~ "business logic"
    end

    test "returns application name" do
      assert Soundboard.app_name() == :soundboard
    end
  end
end
