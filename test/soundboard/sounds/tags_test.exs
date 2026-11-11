defmodule Soundboard.Sounds.TagsTest do
  use Soundboard.DataCase, async: false

  alias Soundboard.Sounds.Tags
  alias Soundboard.Tag

  test "resolve_many/1 normalizes, deduplicates, and ignores nil" do
    assert {:ok, [alpha, beta]} = Tags.resolve_many([" Alpha ", "beta", "alpha", nil])
    assert alpha.name == "alpha"
    assert beta.name == "beta"
  end

  test "resolve/1 rejects blank tag names" do
    assert {:error, changeset} = Tags.resolve("   ")
    assert "can't be blank" in errors_on(changeset).tags
  end

  test "a duplicate tag name is a changeset error, which find_or_create's race fallback needs" do
    assert {:ok, _tag} = Repo.insert(Tag.changeset(%Tag{}, %{name: "dup"}))
    assert {:error, changeset} = Repo.insert(Tag.changeset(%Tag{}, %{name: "dup"}))
    assert %{name: ["has already been taken"]} = errors_on(changeset)
  end
end
