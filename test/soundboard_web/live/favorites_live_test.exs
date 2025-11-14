defmodule SoundboardWeb.FavoritesLiveTest do
  @moduledoc false
  use SoundboardWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Soundboard.Accounts.{Tenant, Tenants, User}
  alias Soundboard.Favorites
  alias Soundboard.Favorites.Favorite
  alias Soundboard.{Repo, Sound}

  setup %{conn: conn} do
    Repo.delete_all(Favorite)
    Repo.delete_all(Sound)
    Repo.delete_all(User)

    tenant = Tenants.ensure_default_tenant!()

    {:ok, user} =
      %User{}
      |> User.changeset(%{
        username: "favorites_user",
        discord_id: "fav-#{System.unique_integer([:positive])}",
        avatar: "fav.jpg",
        tenant_id: tenant.id
      })
      |> Repo.insert()

    {:ok, sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "favorite_sound.mp3",
        source_type: "local",
        user_id: user.id
      })
      |> Repo.insert()

    Favorites.toggle_favorite(user.id, sound.id)

    conn =
      conn
      |> init_test_session(%{user_id: user.id, tenant_id: tenant.id})

    {:ok, conn: conn, tenant: tenant, user: user, sound: sound}
  end

  test "only renders favorites for current tenant", %{conn: conn, user: user, sound: sound} do
    {:ok, other_tenant} =
      %Tenant{}
      |> Tenant.changeset(%{
        name: "Other",
        slug: "favorites-#{System.unique_integer([:positive])}",
        plan: :pro
      })
      |> Repo.insert()

    {:ok, other_user} =
      %User{}
      |> User.changeset(%{
        username: "other_fav_user",
        discord_id: "other-fav-#{System.unique_integer([:positive])}",
        avatar: "fav.jpg",
        tenant_id: other_tenant.id
      })
      |> Repo.insert()

    {:ok, other_sound} =
      %Sound{}
      |> Sound.changeset(%{
        filename: "other_favorite_sound.mp3",
        source_type: "local",
        user_id: other_user.id
      })
      |> Repo.insert()

    # Simulate bad data where the current user has favorited a sound from another tenant
    %Favorite{}
    |> Favorite.changeset(%{user_id: user.id, sound_id: other_sound.id})
    |> Repo.insert()

    {:ok, _view, html} = live(conn, "/favorites")
    assert html =~ sound.filename
    refute html =~ other_sound.filename
  end
end
