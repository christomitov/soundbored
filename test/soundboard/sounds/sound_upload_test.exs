defmodule Soundboard.Sounds.UploadTest do
  @moduledoc """
  Tests the Sound.Upload module.
  """
  use Soundboard.DataCase

  alias Soundboard.Accounts.{Tenants, User}
  alias Soundboard.Repo
  alias Soundboard.Sound

  setup do
    user = insert_user()
    %{user: user}
  end

  describe "upload" do
    test "upload creates sound from local file", %{user: user} do
      attrs = %{
        filename: "test.mp3",
        user_id: user.id,
        source_type: "local"
      }

      {:ok, sound} =
        %Sound{}
        |> Sound.changeset(attrs)
        |> Repo.insert()

      assert sound.filename == "test.mp3"
      assert sound.source_type == "local"
    end

    test "upload creates sound from URL", %{user: user} do
      attrs = %{
        filename: "url_sound.mp3",
        url: "https://example.com/sound.mp3",
        user_id: user.id,
        source_type: "url"
      }

      {:ok, sound} =
        %Sound{}
        |> Sound.changeset(attrs)
        |> Repo.insert()

      assert sound.url == "https://example.com/sound.mp3"
      assert sound.source_type == "url"
    end

    test "validates source type", %{user: user} do
      attrs = %{
        filename: "test.mp3",
        user_id: user.id,
        source_type: "invalid"
      }

      changeset = Sound.changeset(%Sound{}, attrs)
      assert %{source_type: ["must be either 'local' or 'url'"]} = errors_on(changeset)
    end

    test "requires filename for local sounds", %{user: user} do
      attrs = %{
        user_id: user.id,
        source_type: "local"
      }

      changeset = Sound.changeset(%Sound{}, attrs)
      assert %{filename: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # Helper functions
  defp insert_user do
    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %Soundboard.Accounts.User{}
      |> User.changeset(%{
        username: "test_user",
        discord_id: "123456",
        avatar: "test.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    user
  end
end
