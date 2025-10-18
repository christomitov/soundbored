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

const BASE_PERCENT = 100
const MAX_VOLUME_PERCENT_DEFAULT = 150
const BOOST_CAP = 1.5
const SNAP_PERCENT = 100
const SNAP_THRESHOLD = 2

const parsePercent = (value, fallback = MAX_VOLUME_PERCENT_DEFAULT, maxPercent = MAX_VOLUME_PERCENT_DEFAULT) => {
  const normalize = (val) => clamp(Math.round(val), 0, maxPercent)

  if (typeof value === "number" && !Number.isNaN(value)) {
    return normalize(value)
  }

  if (typeof value === "string") {
    const parsed = parseFloat(value.trim())
    if (!Number.isNaN(parsed)) {
      return normalize(parsed)
    }
  }

  const fallbackNumber = typeof fallback === "string" ? parseFloat(fallback) : fallback
  return normalize(Number.isFinite(fallbackNumber) ? fallbackNumber : maxPercent)
}

const percentToDecimal = (percent, maxPercent = MAX_VOLUME_PERCENT_DEFAULT) => {
  const clamped = clamp(percent, 0, maxPercent)

  if (clamped <= BASE_PERCENT) {
    const normalized = clamped / BASE_PERCENT
    const scaled = normalized * normalized
    return clamp(Math.round(scaled * 10000) / 10000, 0, BOOST_CAP)
  }

  const boosted = 1 + (clamped - BASE_PERCENT) * 0.01
  return clamp(Math.round(boosted * 10000) / 10000, 0, BOOST_CAP)
}

const PlayerState = {
  currentHook: null,
  currentAudio: null,
  currentCleanup: null,

  set(hook, audio, cleanup = null) {
    this.currentHook = hook
    this.currentAudio = audio
    this.currentCleanup = cleanup
  },

  stopCurrent() {
    if (this.currentAudio) {
      this.currentAudio.pause()
      this.currentAudio.currentTime = 0
      if (typeof this.currentCleanup === "function") {
        try {
          this.currentCleanup()
        } catch (_err) {}
      }
    }

    if (this.currentHook) {
      this.currentHook.setPlaying(false)
    }

    this.currentHook = null
    this.currentAudio = null
    this.currentCleanup = null
  }
}

window.addEventListener("phx:stop-all-sounds", () => PlayerState.stopCurrent())

let Hooks = {}
Hooks.LocalPlayer = {
  mounted() {
    this.audioContext = null
    this.handleClick = this.handleClick.bind(this)
    this.el.addEventListener("click", this.handleClick)
  },
  updated() {
    if (PlayerState.currentHook === this && PlayerState.currentAudio) {
      this.setElementVolume(PlayerState.currentAudio, this.getVolume())
    }
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    if (PlayerState.currentHook === this) {
      PlayerState.stopCurrent()
    }
  },
  async handleClick(event) {
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
    const volume = this.getVolume()
    const cleanup = await this.applyBoost(audio, volume)

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
        PlayerState.set(this, audio, cleanup)
      })
      .catch((error) => {
        console.error("Audio playback failed", error)
        this.setPlaying(false)
        if (typeof cleanup === "function") {
          try {
            cleanup()
          } catch (_err) {}
        }
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
      return clamp(volume, 0, BOOST_CAP)
    }

    return 1
  },
  setElementVolume(audio, target) {
    if (!audio) {
      return
    }

    const clamped = Math.max(0, Math.min(target, 1))
    try {
      audio.volume = clamped
    } catch (_err) {
      audio.volume = 1
    }

    if (audio.__boostGain) {
      audio.__boostGain.gain.value = target > 1 ? target : 1
    }
  },
  async applyBoost(audio, target) {
    const normalized = Math.max(0, Math.min(target, BOOST_CAP))
    const AudioContextCtor = window.AudioContext || window.webkitAudioContext

    if (!AudioContextCtor || normalized <= 1) {
      this.setElementVolume(audio, normalized)
      return null
    }

    if (!this.audioContext) {
      this.audioContext = new AudioContextCtor()
    }

    if (this.audioContext.state === "suspended") {
      try {
        await this.audioContext.resume()
      } catch (_err) {}
    }

    let source
    let gainNode

    try {
      source = this.audioContext.createMediaElementSource(audio)
      gainNode = this.audioContext.createGain()
      gainNode.gain.value = normalized
      source.connect(gainNode).connect(this.audioContext.destination)
      audio.__boostGain = gainNode
      this.setElementVolume(audio, 1)
    } catch (error) {
      console.error("Failed to apply local boost", error)
      this.setElementVolume(audio, 1)
      return null
    }

    return () => {
      try {
        source.disconnect()
      } catch (_err) {}
      try {
        gainNode.disconnect()
      } catch (_err) {}
      if (audio.__boostGain === gainNode) {
        delete audio.__boostGain
      }
    }
  }
}

Hooks.VolumeControl = {
  mounted() {
    this.maxPercent = parseInt(this.el.dataset.maxPercent || `${MAX_VOLUME_PERCENT_DEFAULT}`, 10)
    if (Number.isNaN(this.maxPercent) || this.maxPercent <= 0) {
      this.maxPercent = MAX_VOLUME_PERCENT_DEFAULT
    }
    this.thumbSize = 18
    this.audioContext = null
    this.previewSource = null
    this.previewGain = null
    this.previewGraphBlocked = false
    this.previewGraphBlockedSource = null
    this.assignElements()
    this.previewAudio = null
    this.objectUrl = null
    this.lastPreviewFile = null
    this.pushDebounce = null
    this.boundSlider = null
    this.boundPreviewButton = null

    this.handleSliderInput = (event) => {
      let percent = parsePercent(event.target.value, this.maxPercent, this.maxPercent)
      percent = this.maybeSnap(percent)
      event.target.value = percent
      this.updateDisplay(percent)
      this.updatePreviewVolume(percent)
      this.updateHidden(percent)
      this.queueVolumePush(percent)
    }

    this.handlePreviewClick = async (event) => {
      event.preventDefault()
      if (this.previewButton && this.previewButton.disabled) {
        return
      }
      await this.togglePreview()
    }

    this.bindSlider()
    this.bindPreviewButton()

    let initialPercent = parsePercent(
      this.slider?.value ?? this.hiddenInput?.value ?? this.maxPercent,
      this.maxPercent,
      this.maxPercent
    )
    initialPercent = this.maybeSnap(initialPercent)
    if (this.slider) {
      this.slider.value = initialPercent
    }
    this.updateDisplay(initialPercent)
    this.updatePreviewVolume(initialPercent)
    this.updateHidden(initialPercent)
  },
  updated() {
    this.assignElements()
    this.bindSlider()
    this.bindPreviewButton()

    if (this.slider) {
      let percent = parsePercent(this.slider.value, this.maxPercent, this.maxPercent)
      percent = this.maybeSnap(percent)
      this.slider.value = percent
      this.updateDisplay(percent)
      this.updatePreviewVolume(percent)
      this.updateHidden(percent)
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
    this.track = this.el.querySelector("[data-role='volume-track']")
    this.marker = this.el.querySelector("[data-role='volume-marker']")
    this.hiddenInput = this.el.querySelector("[data-role='volume-hidden']")
    this.display = this.el.querySelector("[data-role='volume-display']")
    this.previewButton = this.el.querySelector("[data-role='volume-preview']")
    this.pushEventName = this.el.dataset.pushEvent
    this.volumeTarget = this.el.dataset.volumeTarget
    const maxFromDataset = parseInt(this.el.dataset.maxPercent || "", 10)
    if (!Number.isNaN(maxFromDataset) && maxFromDataset > 0) {
      this.maxPercent = maxFromDataset
    }
    if (this.slider) {
      const thumb = parseInt(this.slider.dataset.thumbSize || "", 10)
      if (!Number.isNaN(thumb) && thumb > 0) {
        this.thumbSize = thumb
      }
      this.minPercent = Number(this.slider.min || 0)
      this.maxPercent = Number(this.slider.max || this.maxPercent)
    }
    this.previewKind = this.el.dataset.previewKind || "existing"
    this.fileInputId = this.el.dataset.fileInputId
    this.urlInputId = this.el.dataset.urlInputId
    this.previewSrc = this.el.dataset.previewSrc

    if (previousKind && previousKind !== this.previewKind) {
      this.stopPreview(true)
    } else if (previousSrc && previousSrc !== this.previewSrc && this.previewKind !== "local-upload") {
      this.stopPreview()
    }

    const currentPercent = parsePercent(
      this.hiddenInput?.value ?? this.slider?.value ?? this.maxPercent,
      this.maxPercent,
      this.maxPercent
    )
    this.positionMarker(this.maybeSnap(currentPercent))
  },
  updateDisplay(percent) {
    if (this.display) {
      this.display.textContent = `${percent}%`
      if (percent > BASE_PERCENT) {
        this.display.classList.add("text-amber-500", "font-semibold")
      } else {
        this.display.classList.remove("text-amber-500", "font-semibold")
      }
    }
  },
  updatePreviewVolume(percent) {
    const targetGain = percentToDecimal(percent, this.maxPercent)
    this.ensurePreviewGraph(targetGain).then(() => this.setPreviewLevels(targetGain))
  },
  updateHidden(percent) {
    if (this.hiddenInput) {
      this.hiddenInput.value = percent
    }
    this.positionMarker(percent)
  },
  positionMarker(percent) {
    if (!this.marker || !this.slider) {
      return
    }

    const thumb = this.thumbSize || 18
    const min = this.minPercent ?? Number(this.slider.min || 0)
    const max = this.maxPercent ?? Number(this.slider.max || MAX_VOLUME_PERCENT_DEFAULT)
    const range = max - min
    const ratio = range <= 0 ? 0 : (percent - min) / range
    const boundedRatio = clamp(ratio, 0, 1)
    const containerWidth = (this.track && this.track.clientWidth) || this.slider.clientWidth || 0
    const offset = boundedRatio * Math.max(containerWidth - thumb, 0) + thumb / 2

    this.marker.style.left = `${offset}px`
  },
  maybeSnap(percent) {
    if (Math.abs(percent - SNAP_PERCENT) <= SNAP_THRESHOLD) {
      return SNAP_PERCENT
    }

    return clamp(percent, this.minPercent ?? 0, this.maxPercent ?? MAX_VOLUME_PERCENT_DEFAULT)
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
  async togglePreview() {
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
    const currentSrc = this.previewAudio.currentSrc || this.previewAudio.src || src
    if (
      this.previewGraphBlocked &&
      this.previewGraphBlockedSource &&
      this.previewGraphBlockedSource !== currentSrc
    ) {
      this.previewGraphBlocked = false
      this.previewGraphBlockedSource = null
    }
    const previewPercent = this.maybeSnap(
      parsePercent(this.slider?.value ?? this.maxPercent, this.maxPercent, this.maxPercent)
    )
    const targetGain = percentToDecimal(previewPercent, this.maxPercent)
    await this.ensurePreviewGraph(targetGain)
    this.setPreviewLevels(targetGain)

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
      if (this.previewSource) {
        try {
          this.previewSource.disconnect()
        } catch (_err) {}
        this.previewSource = null
      }
      if (this.previewGain) {
        try {
          this.previewGain.disconnect()
        } catch (_err) {}
        this.previewGain = null
      }
      this.previewGraphBlocked = false
      this.previewGraphBlockedSource = null
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
  },
  async ensurePreviewGraph(targetGain) {
    if (!this.previewAudio) {
      return
    }

    const currentSrc = this.previewAudio.currentSrc || this.previewAudio.src || ""
    if (this.previewGraphBlocked) {
      if (!this.previewGraphBlockedSource || this.previewGraphBlockedSource === currentSrc) {
        if (this.previewGain) {
          this.previewGain.gain.value = 1
        }
        return
      }
      this.previewGraphBlocked = false
      this.previewGraphBlockedSource = null
    }

    const AudioContextCtor = window.AudioContext || window.webkitAudioContext
    const needsBoost = targetGain > 1

    if (!AudioContextCtor || !needsBoost) {
      if (this.previewGain) {
        this.previewGain.gain.value = 1
      }
      if (!needsBoost) {
        return
      }
      this.audioContext = null
      this.previewSource = null
      this.previewGain = null
      return
    }

    if (!this.audioContext) {
      this.audioContext = new AudioContextCtor()
    }

    if (this.audioContext.state === "suspended") {
      try {
        await this.audioContext.resume()
      } catch (_err) {}
    }

    if (!this.previewSource) {
      try {
        this.previewSource = this.audioContext.createMediaElementSource(this.previewAudio)
        this.previewGain = this.audioContext.createGain()
        this.previewSource.connect(this.previewGain).connect(this.audioContext.destination)
      } catch (error) {
        console.warn("Preview gain fallback: unable to create media element source", error)
        if (this.previewSource) {
          try {
            this.previewSource.disconnect()
          } catch (_err) {}
        }
        if (this.previewGain) {
          try {
            this.previewGain.disconnect()
          } catch (_err) {}
        }
        this.previewSource = null
        this.previewGain = null
        this.previewGraphBlocked = true
        this.previewGraphBlockedSource = currentSrc || null
      }
    }
  },
  setPreviewLevels(targetGain) {
    if (!this.previewAudio) {
      return
    }

    const elementVolume = Math.max(0, Math.min(targetGain, 1))
    try {
      this.previewAudio.volume = elementVolume
    } catch (_err) {
      this.previewAudio.volume = 1
    }

    if (this.previewGain) {
      this.previewGain.gain.value = targetGain > 1 ? targetGain : 1
    }
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
