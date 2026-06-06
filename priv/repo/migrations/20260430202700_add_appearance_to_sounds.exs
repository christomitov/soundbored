defmodule Soundboard.Repo.Migrations.AddAppearanceToSounds do
  use Ecto.Migration

  def change do
    alter table(:sounds) do
      add :color, :string
      add :image_filename, :string
    end
  end
end
