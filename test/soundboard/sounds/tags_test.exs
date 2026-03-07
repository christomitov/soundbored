defmodule Soundboard.Sounds.TagsTest do
  use Soundboard.DataCase

  alias Soundboard.Accounts.User
  alias Soundboard.Sounds.Tags
  alias Soundboard.{Repo, Sound, Tag}

  setup do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "tags_user_#{System.unique_integer([:positive])}",
        discord_id: Integer.to_string(System.unique_integer([:positive])),
        avatar: "avatar.png"
      })
      |> Repo.insert()

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "sound_#{System.unique_integer([:positive])}.mp3",
        source_type: "local",
        user_id: user.id,
        volume: 1.0
      })
      |> Repo.insert()

    %{user: user, sound: sound}
  end

  test "search/1 delegates to tag search", %{sound: sound} do
    alpha = insert_tag!("alpha")
    beta = insert_tag!("beta")
    {:ok, _updated_sound} = Tags.update_sound_tags(sound, [alpha, beta])

    assert [result] = Tags.search("alp")
    assert result.name == "alpha"
  end

  test "all_for_sounds/1 deduplicates and sorts tags" do
    alpha = %Tag{id: 2, name: "alpha"}
    beta = %Tag{id: 1, name: "beta"}

    sounds = [
      %{tags: [beta, alpha]},
      %{tags: [alpha]}
    ]

    assert Enum.map(Tags.all_for_sounds(sounds), & &1.name) == ["alpha", "beta"]
  end

  test "count_sounds_with_tag/2 and tag_selected?/2 work on associations" do
    alpha = %Tag{id: 1, name: "alpha"}
    beta = %Tag{id: 2, name: "beta"}

    sounds = [
      %{tags: [alpha]},
      %{tags: [alpha, beta]},
      %{tags: []}
    ]

    assert Tags.count_sounds_with_tag(sounds, alpha) == 2
    assert Tags.count_sounds_with_tag(sounds, beta) == 1
    assert Tags.tag_selected?(alpha, [beta, alpha])
    refute Tags.tag_selected?(%Tag{id: 3, name: "gamma"}, [beta, alpha])
  end

  test "resolve_many/1 normalizes, deduplicates, and ignores nil-like values" do
    assert {:ok, [alpha, beta]} = Tags.resolve_many([" Alpha ", "beta", "alpha", nil])
    assert alpha.name == "alpha"
    assert beta.name == "beta"
  end

  test "resolve/1 rejects blank tag names" do
    assert {:error, changeset} = Tags.resolve("   ")
    assert "can't be blank" in errors_on(changeset).tags
  end

  test "resolve/1 returns existing tag structs and non-binary values safely" do
    tag = insert_tag!("existing")

    assert {:ok, ^tag} = Tags.resolve(tag)
    assert {:ok, nil} = Tags.resolve(:skip)
  end

  test "find_or_create/1 reuses normalized existing tags" do
    tag = insert_tag!("mixed")

    assert {:ok, resolved} = Tags.find_or_create("  MIXED  ")
    assert resolved.id == tag.id
  end

  test "list_for_sound/1 returns tags for matching sounds and [] for missing sounds", %{
    sound: sound
  } do
    alpha = insert_tag!("listed")
    {:ok, _updated_sound} = Tags.update_sound_tags(sound, [alpha])

    assert [%Tag{name: "listed"}] = Tags.list_for_sound(sound.filename)
    assert [] = Tags.list_for_sound("missing.mp3")
  end

  defp insert_tag!(name) do
    %Tag{}
    |> Tag.changeset(%{name: name})
    |> Repo.insert!()
  end
end
