defmodule Soundboard.TenantsTest do
  @moduledoc """
  Behavioral tests for the multi-tenant context: default-guild fallback,
  tenant rows, slug claiming, and storage caps.
  """

  use Soundboard.DataCase, async: false

  import Mock

  alias Soundboard.{Accounts.User, Repo, Sound, Tenants, Tenants.Guild}

  describe "default_guild_id/0" do
    test "falls back to the literal default when nothing is configured" do
      Application.delete_env(:soundboard, :default_guild_id)
      Application.delete_env(:soundboard, :required_guild_id)

      assert Tenants.default_guild_id() == "default"
    end

    test "prefers SOUNDBOARD_DEFAULT_GUILD_ID over DISCORD_REQUIRED_GUILD_ID" do
      Application.put_env(:soundboard, :default_guild_id, "111")
      Application.put_env(:soundboard, :required_guild_id, "222")

      assert Tenants.default_guild_id() == "111"
    after
      Application.delete_env(:soundboard, :default_guild_id)
      Application.delete_env(:soundboard, :required_guild_id)
    end

    test "uses DISCORD_REQUIRED_GUILD_ID when no default is set (back-compat)" do
      Application.delete_env(:soundboard, :default_guild_id)
      Application.put_env(:soundboard, :required_guild_id, "222")

      assert Tenants.default_guild_id() == "222"
    after
      Application.delete_env(:soundboard, :required_guild_id)
    end
  end

  describe "scope_guild_id/1" do
    test "nil resolves to the default guild" do
      assert Tenants.scope_guild_id(nil) == Tenants.default_guild_id()
    end

    test "explicit guild ids pass through" do
      assert Tenants.scope_guild_id("999") == "999"
    end
  end

  describe "default_guild_id/0 zero-config discovery" do
    test "uses the bot's sole guild when no env is configured" do
      Application.delete_env(:soundboard, :default_guild_id)
      Application.delete_env(:soundboard, :required_guild_id)

      with_mock Soundboard.Discord.GuildCache,
        all: fn -> [%{id: "111", name: "g", guild: nil}] end do
        assert Tenants.default_guild_id() == "111"
      end
    end

    test "falls back to the literal default when the bot is in many guilds" do
      Application.delete_env(:soundboard, :default_guild_id)
      Application.delete_env(:soundboard, :required_guild_id)

      with_mock Soundboard.Discord.GuildCache,
        all: fn ->
          [
            %{id: "1", name: "a", guild: nil},
            %{id: "2", name: "b", guild: nil}
          ]
        end do
        assert Tenants.default_guild_id() == "default"
      end
    end

    test "configured env still wins over discovery" do
      Application.delete_env(:soundboard, :default_guild_id)
      Application.put_env(:soundboard, :required_guild_id, "222")

      with_mock Soundboard.Discord.GuildCache,
        all: fn -> [%{id: "111", name: "g", guild: nil}] end do
        assert Tenants.default_guild_id() == "222"
      end
    after
      Application.delete_env(:soundboard, :required_guild_id)
    end
  end

  describe "reconcile_default_guild/0" do
    test "repoints legacy 'default' rows to the bot's sole guild" do
      Application.delete_env(:soundboard, :default_guild_id)
      Application.delete_env(:soundboard, :required_guild_id)

      user = Repo.insert!(%User{discord_id: "u1", username: "u1", avatar: nil})

      sound =
        Repo.insert!(%Sound{
          filename: "legacy.mp3",
          storage_key: "legacy.mp3",
          guild_id: "default",
          user_id: user.id
        })

      with_mock Soundboard.Discord.GuildCache,
        all: fn -> [%{id: "111", name: "g", guild: nil}] end do
        assert {:ok, 1} = Tenants.reconcile_default_guild()
        assert Repo.get(Sound, sound.id).guild_id == "111"
      end
    end

    test "skips when a guild env is configured" do
      Application.put_env(:soundboard, :required_guild_id, "222")

      assert Tenants.reconcile_default_guild() == :skipped
    after
      Application.delete_env(:soundboard, :required_guild_id)
    end
  end

  describe "get_or_create_guild/2" do
    test "creates a tenant row with defaults on first use" do
      {:ok, guild} = Tenants.get_or_create_guild("12345", %{slug: "acme", name: "Acme"})

      assert guild.discord_guild_id == "12345"
      assert guild.slug == "acme"
      assert guild.max_storage_bytes == Tenants.default_storage_bytes()
    end

    test "is idempotent" do
      {:ok, first} = Tenants.get_or_create_guild("12345", %{slug: "acme"})
      assert first.max_storage_bytes == Tenants.default_storage_bytes()
      {:ok, second} = Tenants.get_or_create_guild("12345")

      assert first.id == second.id
      assert Enum.count(Tenants.list_guilds()) == 1
    end

    test "returns the existing row unchanged on subsequent calls" do
      {:ok, first} = Tenants.get_or_create_guild("1", %{slug: "one"})
      {:ok, second} = Tenants.get_or_create_guild("1", %{slug: "uno"})

      assert second.id == first.id
      assert second.slug == "one"
    end
  end

  describe "claim_slug/2" do
    test "claims a slug for a new guild" do
      assert {:ok, %Guild{slug: "my-server"}} = Tenants.claim_slug("777", "My-Server")
    end

    test "normalizes and validates the slug format" do
      assert {:ok, %Guild{slug: "my-server"}} = Tenants.claim_slug("777", "My-Server")
      assert {:error, :invalid_slug} = Tenants.claim_slug("778", "Not A Slug!")
      assert {:error, :invalid_slug} = Tenants.claim_slug("779", "-bad-")
      assert {:error, :invalid_slug} = Tenants.claim_slug("780", "")
    end

    test "rejects reserved slugs" do
      for slug <- Tenants.reserved_slugs() do
        assert {:error, :invalid_slug} = Tenants.claim_slug("777", slug)
      end
    end

    test "rejects slugs claimed by another guild, allows re-claim by same guild" do
      {:ok, _} = Tenants.claim_slug("111", "taken")

      assert {:error, :slug_taken} = Tenants.claim_slug("222", "taken")
      assert {:ok, %Guild{discord_guild_id: "111"}} = Tenants.claim_slug("111", "taken")
    end
  end

  describe "storage caps" do
    setup do
      user = Repo.insert!(%User{discord_id: "t1", username: "tenant-tester"})
      %{user: user}
    end

    test "usage is the sum of known sound sizes for the guild", %{user: user} do
      insert_sound!(user, guild_id: "g1", byte_size: 100)
      insert_sound!(user, guild_id: "g1", byte_size: 250)
      insert_sound!(user, guild_id: "g2", byte_size: 9_000)

      assert Tenants.storage_used("g1") == 350
      assert Tenants.storage_used("g2") == 9_000
    end

    test "unknown-size sounds (legacy rows) count as zero", %{user: user} do
      insert_sound!(user, guild_id: "g1", byte_size: 0)

      assert Tenants.storage_used("g1") == 0
    end

    test "cap comes from the guild row when present" do
      {:ok, _} = Tenants.get_or_create_guild("g1", %{slug: "capped", max_storage_bytes: 1_000})

      assert Tenants.storage_cap("g1") == 1_000
    end

    test "cap falls back to the configured default when no row exists" do
      Application.put_env(:soundboard, :default_storage_bytes, 5_000)

      assert Tenants.storage_cap("unknown-guild") == 5_000
    after
      Application.delete_env(:soundboard, :default_storage_bytes)
    end

    test "within_storage_limit?/2 admits up to the cap and rejects beyond it", %{user: user} do
      {:ok, _} = Tenants.get_or_create_guild("g1", %{slug: "limits", max_storage_bytes: 1_000})
      insert_sound!(user, guild_id: "g1", byte_size: 600)

      assert Tenants.within_storage_limit?("g1", 400)
      refute Tenants.within_storage_limit?("g1", 401)
    end

    test "a guild with no usage can upload its full cap" do
      {:ok, _} = Tenants.get_or_create_guild("g2", %{slug: "fresh", max_storage_bytes: 500})

      assert Tenants.storage_remaining("g2") == 500
      assert Tenants.within_storage_limit?("g2", 500)
      refute Tenants.within_storage_limit?("g2", 501)
    end
  end

  defp insert_sound!(user, attrs) do
    defaults = [
      filename: "sound-#{System.unique_integer([:positive])}.mp3",
      storage_key: Ecto.UUID.generate() <> ".mp3",
      source_type: "url",
      url: "https://example.com/sound.mp3",
      user_id: user.id
    ]

    %Soundboard.Sound{}
    |> Soundboard.Sound.changeset(Map.new(Enum.concat(defaults, attrs)))
    |> Repo.insert!()
  end
end
