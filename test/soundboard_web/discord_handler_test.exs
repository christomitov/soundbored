defmodule SoundboardWeb.DiscordHandlerTest do
  @moduledoc """
  Tests the DiscordHandler module.
  """
  use Soundboard.DataCase
  alias Soundboard.Accounts.{Guilds, Tenant, Tenants, User}
  alias SoundboardWeb.DiscordHandler
  import Mock
  import ExUnit.CaptureLog

  setup do
    original = Application.get_env(:soundboard, :edition, :community)

    on_exit(fn ->
      Application.put_env(:soundboard, :edition, original)
    end)

    :ok
  end

  describe "handle_event/1" do
    test "handles voice state updates" do
      # State GenServer is already started by the application
      # Set up the persistent term to simulate bot being ready
      :persistent_term.put(:soundboard_bot_ready, true)

      # Clean up after test
      on_exit(fn ->
        :persistent_term.erase(:soundboard_bot_ready)
      end)

      mock_guild = %{
        id: "456",
        voice_states: [
          %{
            user_id: "789",
            channel_id: "123",
            guild_id: "456",
            session_id: "abc"
          }
        ]
      }

      capture_log(fn ->
        with_mocks([
          {Nostrum.Voice, [],
           [
             join_channel: fn _, _ -> :ok end,
             ready?: fn _ -> false end
           ]},
          {Nostrum.Cache.GuildCache, [], [get!: fn _guild_id -> mock_guild end]},
          {Nostrum.Api.Self, [], [get: fn -> {:ok, %{id: "999"}} end]}
        ]) do
          payload = %{
            channel_id: "123",
            guild_id: "456",
            user_id: "789",
            session_id: "abc"
          }

          tenant = Tenants.ensure_default_tenant!()
          {:ok, _} = Guilds.associate_guild(tenant, payload.guild_id)

          # Call the handle_event function directly since it's a callback, not a GenServer
          DiscordHandler.handle_event({:VOICE_STATE_UPDATE, payload, nil})

          # Assert that appropriate actions were taken
          assert_called(Nostrum.Voice.join_channel("456", "123"))
        end
      end)
    end

    test "voice state updates are ignored when guild mapping is missing" do
      payload = %{
        channel_id: "123",
        guild_id: "missing",
        user_id: "789",
        session_id: "abc"
      }

      log =
        with_mock Nostrum.Api.Self, [], get: fn -> {:ok, %{id: "bot"}} end do
          capture_log(fn ->
            DiscordHandler.handle_event({:VOICE_STATE_UPDATE, payload, nil})
          end)
        end

      assert log =~ "Missing guild mapping"
    end
  end

  describe "guild lifecycle" do
    test "community edition associates guilds with the default tenant" do
      Application.put_env(:soundboard, :edition, :community)
      tenant = Tenants.ensure_default_tenant!()

      DiscordHandler.handle_event({:GUILD_CREATE, %{id: 123, owner_id: 999}, nil})

      assert {:ok, mapped} = Guilds.get_tenant_for_guild("123")
      assert mapped.id == tenant.id
    end

    test "pro edition associates guild using owner tenant" do
      Application.put_env(:soundboard, :edition, :pro)

      {:ok, tenant} =
        %Tenant{}
        |> Tenant.changeset(%{
          name: "Pro Tenant",
          slug: "pro-tenant-#{System.unique_integer([:positive])}",
          plan: :pro
        })
        |> Repo.insert()

      owner_id = Integer.to_string(System.unique_integer([:positive]))

      {:ok, _user} =
        %User{}
        |> User.changeset(%{
          discord_id: owner_id,
          username: "owner",
          avatar: "owner.jpg",
          tenant_id: tenant.id
        })
        |> Repo.insert()

      DiscordHandler.handle_event({
        :GUILD_CREATE,
        %{id: 456, owner_id: String.to_integer(owner_id)},
        nil
      })

      assert {:ok, mapped} = Guilds.get_tenant_for_guild("456")
      assert mapped.id == tenant.id
    end

    test "pro edition logs when owner tenant cannot be resolved" do
      Application.put_env(:soundboard, :edition, :pro)

      log =
        capture_log(fn ->
          DiscordHandler.handle_event({:GUILD_CREATE, %{id: 789, owner_id: 111}, nil})
        end)

      assert log =~ "owner"
      assert {:error, :not_found} = Guilds.get_tenant_for_guild("789")
    end

    test "guild delete removes mapping" do
      tenant = Tenants.ensure_default_tenant!()
      {:ok, _} = Guilds.associate_guild(tenant, "999")

      DiscordHandler.handle_event({:GUILD_DELETE, %{id: "999"}, nil})

      assert {:error, :not_found} = Guilds.get_tenant_for_guild("999")
    end
  end
end
