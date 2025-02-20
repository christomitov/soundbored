// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Add this to your hooks
let Hooks = {}
Hooks.LocalPlayer = {
  mounted() {
    this.audio = null;
    
    this.el.addEventListener("click", e => {
      e.preventDefault()
      e.stopPropagation()
      
      if (this.audio && !this.audio.paused) {
        this.audio.pause()
        this.audio.currentTime = 0
        this.el.querySelector('.play-icon').classList.remove('hidden')
        this.el.querySelector('.stop-icon').classList.add('hidden')
        return
      }
      
      const filename = this.el.dataset.filename
      const sourceType = this.el.dataset.sourceType
      const url = this.el.dataset.url
      
      this.audio = new Audio()
      
      if (sourceType === "url") {
        this.audio.src = url
      } else {
        this.audio.src = `/uploads/${filename}`
      }
      
      this.audio.play()
      this.el.querySelector('.play-icon').classList.add('hidden')
      this.el.querySelector('.stop-icon').classList.remove('hidden')
      
      this.audio.onended = () => {
        this.el.querySelector('.play-icon').classList.remove('hidden')
        this.el.querySelector('.stop-icon').classList.add('hidden')
      }
    })
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

if (window.navigator.standalone) {
  document.documentElement.style.setProperty('--sat', 'env(safe-area-inset-top)');
  document.documentElement.classList.add('standalone');
}

