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

const clamp = (value, min, max) => Math.min(Math.max(value, min), max)

const parsePercent = (value, fallback = 100) => {
  if (typeof value === "number" && !Number.isNaN(value)) {
    return clamp(Math.round(value), 0, 100)
  }

  if (typeof value === "string") {
    const parsed = parseFloat(value.trim())
    if (!Number.isNaN(parsed)) {
      return clamp(Math.round(parsed), 0, 100)
    }
  }

  return clamp(Math.round(fallback), 0, 100)
}

const percentToDecimal = (percent) => clamp(percent / 100, 0, 1)

const PlayerState = {
  currentHook: null,
  currentAudio: null,

  set(hook, audio) {
    this.currentHook = hook
    this.currentAudio = audio
  },

  stopCurrent() {
    if (this.currentAudio) {
      this.currentAudio.pause()
      this.currentAudio.currentTime = 0
    }

    if (this.currentHook) {
      this.currentHook.setPlaying(false)
    }

    this.currentHook = null
    this.currentAudio = null
  }
}

window.addEventListener("phx:stop-all-sounds", () => PlayerState.stopCurrent())

let Hooks = {}
Hooks.LocalPlayer = {
  mounted() {
    this.handleClick = this.handleClick.bind(this)
    this.el.addEventListener("click", this.handleClick)
  },
  updated() {
    if (PlayerState.currentHook === this && PlayerState.currentAudio) {
      PlayerState.currentAudio.volume = this.getVolume()
    }
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    if (PlayerState.currentHook === this) {
      PlayerState.stopCurrent()
    }
  },
  handleClick(event) {
    event.preventDefault()
    event.stopPropagation()

    if (PlayerState.currentHook === this && PlayerState.currentAudio) {
      PlayerState.stopCurrent()
      return
    }

    PlayerState.stopCurrent()

    const sourceType = this.el.dataset.sourceType
    const url = this.el.dataset.url
    const filename = this.el.dataset.filename
    const audio = new Audio()
    audio.volume = this.getVolume()

    if (sourceType === "url" && url) {
      audio.src = url
    } else {
      audio.src = `/uploads/${filename}`
    }

    audio.onended = () => {
      if (PlayerState.currentHook === this) {
        PlayerState.stopCurrent()
      }
    }

    audio.onerror = () => {
      if (PlayerState.currentHook === this) {
        PlayerState.stopCurrent()
      }
    }

    audio
      .play()
      .then(() => {
        this.setPlaying(true)
        PlayerState.set(this, audio)
      })
      .catch((error) => {
        console.error("Audio playback failed", error)
        this.setPlaying(false)
      })
  },
  setPlaying(isPlaying) {
    const playIcon = this.el.querySelector(".play-icon")
    const stopIcon = this.el.querySelector(".stop-icon")

    if (!playIcon || !stopIcon) {
      return
    }

    if (isPlaying) {
      playIcon.classList.add("hidden")
      stopIcon.classList.remove("hidden")
    } else {
      playIcon.classList.remove("hidden")
      stopIcon.classList.add("hidden")
    }
  },
  getVolume() {
    const volume = parseFloat(this.el.dataset.volume)
    if (Number.isFinite(volume)) {
      return clamp(volume, 0, 1)
    }

    return 1
  }
}

Hooks.VolumeControl = {
  mounted() {
    this.assignElements()
    this.previewAudio = null
    this.objectUrl = null
    this.lastPreviewFile = null
    this.pushDebounce = null
    this.boundSlider = null
    this.boundPreviewButton = null

    this.handleSliderInput = (event) => {
      const percent = parsePercent(event.target.value)
      this.updateDisplay(percent)
      this.updatePreviewVolume(percent)
      this.queueVolumePush(percent)
    }

    this.handlePreviewClick = (event) => {
      event.preventDefault()
      if (this.previewButton && this.previewButton.disabled) {
        return
      }
      this.togglePreview()
    }

    this.bindSlider()
    this.bindPreviewButton()

    const initialPercent = parsePercent(this.slider?.value ?? 100)
    this.updateDisplay(initialPercent)
    this.updatePreviewVolume(initialPercent)
  },
  updated() {
    this.assignElements()
    this.bindSlider()
    this.bindPreviewButton()

    if (this.slider) {
      const percent = parsePercent(this.slider.value)
      this.updateDisplay(percent)
      this.updatePreviewVolume(percent)
    }
  },
  destroyed() {
    if (this.boundSlider) {
      this.boundSlider.removeEventListener("input", this.handleSliderInput)
      this.boundSlider = null
    }

    if (this.boundPreviewButton) {
      this.boundPreviewButton.removeEventListener("click", this.handlePreviewClick)
      this.boundPreviewButton = null
    }

    this.stopPreview(true)

    if (this.pushDebounce) {
      clearTimeout(this.pushDebounce)
      this.pushDebounce = null
    }
  },
  assignElements() {
    const previousKind = this.previewKind
    const previousSrc = this.previewSrc

    this.slider = this.el.querySelector("[data-role='volume-slider']")
    this.display = this.el.querySelector("[data-role='volume-display']")
    this.previewButton = this.el.querySelector("[data-role='volume-preview']")
    this.pushEventName = this.el.dataset.pushEvent
    this.volumeTarget = this.el.dataset.volumeTarget
    this.previewKind = this.el.dataset.previewKind || "existing"
    this.fileInputId = this.el.dataset.fileInputId
    this.urlInputId = this.el.dataset.urlInputId
    this.previewSrc = this.el.dataset.previewSrc

    if (previousKind && previousKind !== this.previewKind) {
      this.stopPreview(true)
    } else if (previousSrc && previousSrc !== this.previewSrc && this.previewKind !== "local-upload") {
      this.stopPreview()
    }
  },
  updateDisplay(percent) {
    if (this.display) {
      this.display.textContent = `${percent}%`
    }
  },
  updatePreviewVolume(percent) {
    if (this.previewAudio) {
      this.previewAudio.volume = percentToDecimal(percent)
    }
  },
  queueVolumePush(percent) {
    if (!this.pushEventName) {
      return
    }

    if (this.pushDebounce) {
      clearTimeout(this.pushDebounce)
    }

    this.pushDebounce = setTimeout(() => {
    const payload = {volume: percent}
    if (this.volumeTarget) {
      payload.target = this.volumeTarget
    }

    this.pushEvent(this.pushEventName, payload)
    }, 100)
  },
  bindSlider() {
    if (!this.slider) {
      if (this.boundSlider) {
        this.boundSlider.removeEventListener("input", this.handleSliderInput)
      }
      this.boundSlider = null
      return
    }

    if (this.boundSlider === this.slider) {
      return
    }

    if (this.boundSlider) {
      this.boundSlider.removeEventListener("input", this.handleSliderInput)
    }

    this.slider.addEventListener("input", this.handleSliderInput)
    this.boundSlider = this.slider
  },
  bindPreviewButton() {
    if (!this.previewButton) {
      if (this.boundPreviewButton) {
        this.boundPreviewButton.removeEventListener("click", this.handlePreviewClick)
      }
      this.boundPreviewButton = null
      return
    }

    if (this.boundPreviewButton === this.previewButton) {
      return
    }

    if (this.boundPreviewButton) {
      this.boundPreviewButton.removeEventListener("click", this.handlePreviewClick)
    }

    this.previewButton.addEventListener("click", this.handlePreviewClick)
    this.boundPreviewButton = this.previewButton
  },
  togglePreview() {
    if (this.previewAudio && !this.previewAudio.paused) {
      this.stopPreview()
      return
    }

    const src = this.getPreviewSource()
    if (!src) {
      return
    }

    if (!this.previewAudio) {
      this.previewAudio = new Audio()
      this.previewAudio.addEventListener("ended", () => this.stopPreview())
      this.previewAudio.addEventListener("error", () => this.stopPreview())
    }

    this.previewAudio.src = src
    this.previewAudio.volume = percentToDecimal(parsePercent(this.slider?.value ?? 100))

    this.previewAudio
      .play()
      .then(() => this.setPreviewState(true))
      .catch((error) => {
        console.error("Preview playback failed", error)
        this.setPreviewState(false)
      })
  },
  stopPreview(forceRevoke = false) {
    if (this.previewAudio) {
      this.previewAudio.pause()
      this.previewAudio.currentTime = 0
    }

    if (forceRevoke && this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
      this.lastPreviewFile = null
    }

    if (forceRevoke) {
      this.previewAudio = null
    }

    this.setPreviewState(false)
  },
  setPreviewState(isPlaying) {
    if (!this.previewButton) {
      return
    }

    this.previewButton.textContent = isPlaying ? "Stop Preview" : "Preview"
    this.previewButton.dataset.previewState = isPlaying ? "playing" : "stopped"

    if (!isPlaying && this.previewAudio) {
      this.previewAudio.src = ""
    }
  },
  getPreviewSource() {
    if (this.previewKind === "local-upload" && this.fileInputId) {
      const input = document.getElementById(this.fileInputId)
      const file = input && input.files && input.files[0]

      if (!file) {
        return null
      }

      if (this.lastPreviewFile !== file) {
        if (this.objectUrl) {
          URL.revokeObjectURL(this.objectUrl)
        }

        this.objectUrl = URL.createObjectURL(file)
        this.lastPreviewFile = file
      }

      return this.objectUrl
    }

    if (this.previewKind === "url") {
      if (this.urlInputId) {
        const urlInput = document.getElementById(this.urlInputId)
        const value = urlInput && urlInput.value.trim()
        if (value) {
          return value
        }
      }

      return this.previewSrc || null
    }

    return this.previewSrc || null
  }
}

Hooks.CopyButton = {
  mounted() {
    this.handleClick = async (e) => {
      e.preventDefault()
      const original = this.el.textContent
      const text = this.el.dataset.copyText || this.el.getAttribute('data-copy-text')
        || (this.el.nextElementSibling ? this.el.nextElementSibling.innerText : '')
      try {
        if (navigator.clipboard && window.isSecureContext) {
          await navigator.clipboard.writeText(text)
        } else {
          // Fallback for insecure contexts
          const ta = document.createElement('textarea')
          ta.value = text
          ta.style.position = 'fixed'
          ta.style.opacity = '0'
          document.body.appendChild(ta)
          ta.select()
          document.execCommand('copy')
          document.body.removeChild(ta)
        }
        this.el.textContent = 'Copied!'
        this.el.classList.add('text-green-600')
        setTimeout(() => {
          this.el.textContent = original
          this.el.classList.remove('text-green-600')
        }, 1500)
      } catch (_err) {
        this.el.textContent = 'Copy failed'
        this.el.classList.add('text-red-600')
        setTimeout(() => {
          this.el.textContent = original
          this.el.classList.remove('text-red-600')
        }, 1500)
      }
    }
    this.el.addEventListener('click', this.handleClick)
  },
  destroyed() {
    this.el.removeEventListener('click', this.handleClick)
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
