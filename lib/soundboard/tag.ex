defmodule Soundboard.Tag do
  @moduledoc """
  The Tag module.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Soundboard.Accounts.Tenant

  schema "tags" do
    field :name, :string
    belongs_to :tenant, Tenant

    many_to_many :sounds, Soundboard.Sound,
      join_through: Soundboard.SoundTag,
      on_replace: :delete

    timestamps()
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :tenant_id])
    |> validate_required([:name, :tenant_id])
    |> assoc_constraint(:tenant)
    |> unique_constraint(:name, name: :tags_tenant_id_name_index)
  end

  def search(query \\ __MODULE__, search_term, tenant_id) do
    from t in query,
      where:
        t.tenant_id == ^tenant_id and
          like(fragment("lower(?)", t.name), ^"%#{String.downcase(search_term)}%"),
      order_by: t.name,
      limit: 10
  end
end
