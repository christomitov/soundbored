const ClickFeedback = {
  mounted() {
    this.clicks = 0;
    this.el.addEventListener("click", () => {
      this.clicks++;
      console.log(`Clicks: ${this.clicks} for ${this.el.dataset.username}`);
      if (this.clicks === 3) {
        console.log("Sending cycle_user_color event");
        this.pushEvent("cycle_user_color", { username: this.el.dataset.username });
        this.clicks = 0;
      }
    });
  },
  destroyed() {
    this.clicks = 0;
  }
};

export default ClickFeedback; 