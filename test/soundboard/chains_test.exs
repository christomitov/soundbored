defmodule Soundboard.ChainsTest do
  use Soundboard.DataCase

  alias Soundboard.Accounts.User
  alias Soundboard.{Chains, Repo, Sound}

  describe "chains context" do
    setup do
      user = insert_user(%{username: "owner", discord_id: "owner-1"})
      other_user = insert_user(%{username: "other", discord_id: "other-1"})
      sound_a = insert_sound(user, %{filename: "a.mp3"})
      sound_b = insert_sound(user, %{filename: "b.mp3"})
      sound_c = insert_sound(other_user, %{filename: "c.mp3"})

      %{user: user, other_user: other_user, sound_a: sound_a, sound_b: sound_b, sound_c: sound_c}
    end

    test "create_chain/2 stores ordered sound ids and allows duplicates", %{
      user: user,
      sound_a: sound_a,
      sound_b: sound_b
    } do
      assert {:ok, chain} =
               Chains.create_chain(user.id, %{
                 name: "Hype",
                 sound_ids: [sound_a.id, sound_b.id, sound_a.id],
                 is_public: false
               })

      assert chain.name == "Hype"
      assert chain.is_public == false
      assert Enum.map(chain.chain_items, & &1.position) == [0, 1, 2]
      assert Enum.map(chain.chain_items, & &1.sound_id) == [sound_a.id, sound_b.id, sound_a.id]
    end

    test "chain names are unique per user", %{user: user, sound_a: sound_a} do
      assert {:ok, _chain} =
               Chains.create_chain(user.id, %{
                 name: "Unique Name",
                 sound_ids: [sound_a.id]
               })

      assert {:error, changeset} =
               Chains.create_chain(user.id, %{
                 name: "Unique Name",
                 sound_ids: [sound_a.id]
               })

      assert "has already been taken" in errors_on(changeset).name
    end

    test "same chain name can exist for different users", %{
      user: user,
      other_user: other_user,
      sound_a: sound_a,
      sound_c: sound_c
    } do
      assert {:ok, _chain} =
               Chains.create_chain(user.id, %{
                 name: "Shared",
                 sound_ids: [sound_a.id]
               })

      assert {:ok, _chain} =
               Chains.create_chain(other_user.id, %{
                 name: "Shared",
                 sound_ids: [sound_c.id]
               })
    end

    test "list_public_chains/1 excludes current user chains", %{
      user: user,
      other_user: other_user,
      sound_a: sound_a,
      sound_c: sound_c
    } do
      assert {:ok, own_public} =
               Chains.create_chain(user.id, %{
                 name: "Mine Public",
                 sound_ids: [sound_a.id],
                 is_public: true
               })

      assert {:ok, other_public} =
               Chains.create_chain(other_user.id, %{
                 name: "Other Public",
                 sound_ids: [sound_c.id],
                 is_public: true
               })

      chains = Chains.list_public_chains(user.id)
      ids = Enum.map(chains, & &1.id)

      refute own_public.id in ids
      assert other_public.id in ids
    end

    test "get_playable_chain/2 returns public chains from other users", %{
      user: user,
      other_user: other_user,
      sound_c: sound_c
    } do
      assert {:ok, public_chain} =
               Chains.create_chain(other_user.id, %{
                 name: "Open",
                 sound_ids: [sound_c.id],
                 is_public: true
               })

      assert {:ok, chain} = Chains.get_playable_chain(user.id, public_chain.id)
      assert chain.id == public_chain.id
    end

    test "delete_chain/2 only allows owner delete", %{
      user: user,
      other_user: other_user,
      sound_a: sound_a
    } do
      assert {:ok, chain} =
               Chains.create_chain(user.id, %{
                 name: "Delete Me",
                 sound_ids: [sound_a.id]
               })

      assert {:error, :not_found} = Chains.delete_chain(other_user.id, chain.id)
      assert Repo.get(Soundboard.Chains.Chain, chain.id)

      assert {:ok, _} = Chains.delete_chain(user.id, chain.id)
      refute Repo.get(Soundboard.Chains.Chain, chain.id)
    end
  end

  defp insert_user(attrs) do
    base = %{
      username: "user#{System.unique_integer()}",
      discord_id: "discord#{System.unique_integer()}"
    }

    {:ok, user} =
      %User{}
      |> User.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    user
  end

  defp insert_sound(user, attrs \\ %{}) do
    base = %{
      filename: "sound#{System.unique_integer()}.mp3",
      source_type: "local",
      user_id: user.id
    }

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(Map.merge(base, attrs))
      |> Repo.insert()

    sound
  end
end
