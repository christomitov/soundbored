defmodule SoundboardWeb.Soundboard.SoundFilterTest do
  use ExUnit.Case, async: true

  alias SoundboardWeb.Soundboard.SoundFilter

  describe "filter_sounds/3" do
    test "keeps sounds matching every selected tag" do
      alpha = %{id: 1, name: "alpha"}
      beta = %{id: 2, name: "beta"}

      sounds = [
        %{filename: "alpha-beta.mp3", tags: [alpha, beta]},
        %{filename: "alpha-only.mp3", tags: [alpha]},
        %{filename: "beta-only.mp3", tags: [beta]}
      ]

      assert [matched] = SoundFilter.filter_sounds(sounds, "", [alpha, beta])
      assert matched.filename == "alpha-beta.mp3"
    end

    test "matches against filenames and tag names" do
      alpha = %{id: 1, name: "alpha"}
      reaction = %{id: 2, name: "reaction"}

      sounds = [
        %{filename: "victory.mp3", tags: [alpha]},
        %{filename: "sad-trombone.mp3", tags: [reaction]}
      ]

      assert [%{filename: "victory.mp3"}] = SoundFilter.filter_sounds(sounds, "victory", [])

      assert [%{filename: "sad-trombone.mp3"}] =
               SoundFilter.filter_sounds(sounds, "reaction", [])
    end
  end
end
