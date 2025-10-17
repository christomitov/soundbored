defmodule Soundboard.Repo.Migrations.AddVolumeToSounds do
  use Ecto.Migration

  def change do
    alter table(:sounds) do
      add :volume, :float, default: 1.0, null: false
    end
  end
end
