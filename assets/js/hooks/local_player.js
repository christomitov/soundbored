const LocalPlayer = {
  currentAudio: null,
  currentButton: null,

  mounted() {
    this.el.addEventListener("click", () => {
      const filename = this.el.dataset.filename;
      
      // If clicking the same button that's currently playing
      if (LocalPlayer.currentButton === this.el && LocalPlayer.currentAudio) {
        // Stop the audio and reset the button
        LocalPlayer.currentAudio.pause();
        LocalPlayer.currentAudio.currentTime = 0;
        LocalPlayer.currentAudio = null;
        this.updateIcon(false);
        LocalPlayer.currentButton = null;
        return;
      }

      // If a different audio is playing, stop it and reset its button
      if (LocalPlayer.currentAudio && LocalPlayer.currentButton) {
        LocalPlayer.currentAudio.pause();
        LocalPlayer.currentAudio.currentTime = 0;
        LocalPlayer.currentButton.querySelector('svg').outerHTML = this.playIcon();
      }

      // Play the new audio
      LocalPlayer.currentAudio = new Audio(`/uploads/${filename}`);
      LocalPlayer.currentButton = this.el;
      LocalPlayer.currentAudio.play();
      this.updateIcon(true);

      // When audio ends, reset the button
      LocalPlayer.currentAudio.onended = () => {
        this.updateIcon(false);
        LocalPlayer.currentAudio = null;
        LocalPlayer.currentButton = null;
      };
    });
  },

  updateIcon(isPlaying) {
    this.el.querySelector('svg').outerHTML = isPlaying ? this.stopIcon() : this.playIcon();
  },

  playIcon() {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
      <path d="M12 15a3 3 0 100-6 3 3 0 000 6z" />
      <path fill-rule="evenodd" d="M1.323 11.447C2.811 6.976 7.028 3.75 12.001 3.75c4.97 0 9.185 3.223 10.675 7.69.12.362.12.752 0 1.113-1.487 4.471-5.705 7.697-10.677 7.697-4.97 0-9.186-3.223-10.675-7.69a1.762 1.762 0 010-1.113zM17.25 12a5.25 5.25 0 11-10.5 0 5.25 5.25 0 0110.5 0z" clip-rule="evenodd" />
    </svg>`;
  },

  stopIcon() {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
      <path fill-rule="evenodd" d="M4.5 7.5a3 3 0 013-3h9a3 3 0 013 3v9a3 3 0 01-3 3h-9a3 3 0 01-3-3v-9z" clip-rule="evenodd" />
    </svg>`;
  }
}

export default LocalPlayer; 