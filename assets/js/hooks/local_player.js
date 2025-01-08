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
      <path fill-rule="evenodd" d="M4.5 5.653c0-1.427 1.529-2.33 2.779-1.643l11.54 6.347c1.295.712 1.295 2.573 0 3.286L7.28 19.99c-1.25.687-2.779-.217-2.779-1.643V5.653Z" clip-rule="evenodd" />
    </svg>`;
  },

  stopIcon() {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4">
      <path fill-rule="evenodd" d="M4.5 7.5a3 3 0 013-3h9a3 3 0 013 3v9a3 3 0 01-3 3h-9a3 3 0 01-3-3v-9z" clip-rule="evenodd" />
    </svg>`;
  }
}

export default LocalPlayer; 