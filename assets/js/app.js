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
// esbuild treats the UMD build as CommonJS, so window.Hls is never set —
// import the constructor directly instead.
import Hls from "../vendor/hls.min.js"

const HlsCtor = () => Hls || window.Hls

// Discord audio (YouTube URL → ffmpeg → Opus → RTP) typically trails the
// browser remux edge by a few seconds. Hold the muted video back by this
// amount so lips stay closer to Discord.
const LIVE_AV_OFFSET_SEC = 3.5

// The server position is a snapshot. HLS can take a noticeable amount of time
// to attach after that snapshot arrives, so keep advancing the target locally
// and periodically correct media stalls instead of seeking to stale time.
const VIDEO_SYNC_INTERVAL_MS = 500
const VIDEO_HARD_DRIFT_SEC = 0.6
const VIDEO_SOFT_DRIFT_SEC = 0.08
const VIDEO_MAX_RATE_ADJUSTMENT = 0.08

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const clamp = (value, min, max) => Math.min(Math.max(value, min), max)
const roundTo = (value, decimals = 4) => {
  const factor = Math.pow(10, decimals)
  return Math.round(value * factor) / factor
}

const MAX_VOLUME_PERCENT_DEFAULT = 150
const BOOST_CAP = 1.5

const getAudioContextCtor = () => window.AudioContext || window.webkitAudioContext || null

const parsePercent = (
  value,
  fallback = MAX_VOLUME_PERCENT_DEFAULT,
  maxPercent = MAX_VOLUME_PERCENT_DEFAULT
) => {
  const parseNumeric = (input) => {
    if (typeof input === "number" && Number.isFinite(input)) {
      return input
    }
    if (typeof input === "string") {
      const parsed = parseFloat(input.trim())
      if (!Number.isNaN(parsed)) {
        return parsed
      }
    }
    return null
  }

  const parsedValue = parseNumeric(value)
  const parsedFallback = parseNumeric(fallback)
  const base = parsedValue === null ? (parsedFallback === null ? maxPercent : parsedFallback) : parsedValue
  return clamp(Math.round(base), 0, maxPercent)
}

const percentToGain = (percent, maxPercent = MAX_VOLUME_PERCENT_DEFAULT) => {
  const clampedPercent = clamp(Math.round(percent), 0, maxPercent)
  if (clampedPercent <= 100) {
    return roundTo(clampedPercent / 100)
  }
  const boosted = 1 + (clampedPercent - 100) * 0.01
  return roundTo(Math.min(boosted, BOOST_CAP))
}

const setElementGain = (audio, gain) => {
  if (!audio) {
    return
  }

  const clampedGain = clamp(gain, 0, BOOST_CAP)
  const elementVolume = Math.min(clampedGain, 1)

  try {
    audio.volume = elementVolume
  } catch (_err) {
    audio.volume = 1
  }

  if (audio.__gainNode) {
    audio.__gainNode.gain.value = clampedGain > 1 ? clampedGain : 1
  }
}

let activeLocalPlayer = null

const stopActiveLocalPlayer = () => {
  if (activeLocalPlayer && typeof activeLocalPlayer.stopPlayback === "function") {
    activeLocalPlayer.stopPlayback()
  }
}

window.addEventListener("phx:stop-all-sounds", stopActiveLocalPlayer)

let Hooks = {}
Hooks.LocalPlayer = {
  mounted() {
    this.audio = null
    this.audioContext = null
    this.cleanup = null
    this.handleClick = this.handleClick.bind(this)
    this.el.addEventListener("click", this.handleClick)
  },
  updated() {
    if (this.audio && !this.audio.paused) {
      this.configureGain(this.readGain())
    }
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
    this.stopPlayback()
  },
  readGain() {
    const raw = parseFloat(this.el.dataset.volume)
    return Number.isFinite(raw) ? clamp(raw, 0, BOOST_CAP) : 1
  },
  async handleClick(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.audio && !this.audio.paused) {
      this.stopPlayback()
      return
    }

    if (activeLocalPlayer && activeLocalPlayer !== this) {
      activeLocalPlayer.stopPlayback()
    }

    await this.startPlayback()
  },
  async startPlayback() {
    this.stopPlayback()

    const sourceType = this.el.dataset.sourceType
    const url = this.el.dataset.url
    const filename = this.el.dataset.filename

    const audio = new Audio()

    if (sourceType === "url" && url) {
      audio.src = url
    } else if (filename) {
      audio.src = `/uploads/${filename}`
    } else {
      return
    }

    audio.addEventListener("ended", () => this.stopPlayback())
    audio.addEventListener("error", () => this.stopPlayback())

    this.audio = audio

    await this.configureGain(this.readGain())

    try {
      await audio.play()
      this.setPlaying(true)
      activeLocalPlayer = this
    } catch (error) {
      console.error("Audio playback failed", error)
      this.stopPlayback()
    }
  },
  async configureGain(targetGain) {
    if (!this.audio) {
      return
    }

    this.releaseBoost()

    const normalized = clamp(targetGain, 0, BOOST_CAP)
    const ContextCtor = getAudioContextCtor()

    if (!ContextCtor || normalized <= 1) {
      setElementGain(this.audio, normalized)
      return
    }

    if (!this.audioContext) {
      this.audioContext = new ContextCtor()
    }

    if (this.audioContext.state === "suspended") {
      try {
        await this.audioContext.resume()
      } catch (_err) {}
    }

    try {
      const source = this.audioContext.createMediaElementSource(this.audio)
      const gainNode = this.audioContext.createGain()
      gainNode.gain.value = normalized
      source.connect(gainNode).connect(this.audioContext.destination)
      this.audio.__gainNode = gainNode
      setElementGain(this.audio, normalized)

      this.cleanup = () => {
        try {
          source.disconnect()
        } catch (_err) {}
        try {
          gainNode.disconnect()
        } catch (_err) {}
        if (this.audio && this.audio.__gainNode === gainNode) {
          delete this.audio.__gainNode
        }
      }
    } catch (error) {
      console.warn("Unable to apply playback boost", error)
      setElementGain(this.audio, Math.min(normalized, 1))
    }
  },
  releaseBoost() {
    if (typeof this.cleanup === "function") {
      try {
        this.cleanup()
      } catch (_err) {}
    }
    this.cleanup = null
    if (this.audio) {
      delete this.audio.__gainNode
    }
  },
  stopPlayback() {
    this.releaseBoost()
    if (this.audio) {
      try {
        this.audio.pause()
        this.audio.currentTime = 0
      } catch (_err) {}
      this.audio = null
    }
    this.setPlaying(false)
    if (activeLocalPlayer === this) {
      activeLocalPlayer = null
    }
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
  }
}

Hooks.VolumeControl = {
  mounted() {
    this.previewAudio = null
    this.previewContext = null
    this.previewSource = null
    this.previewGain = null
    this.objectUrl = null
    this.lastFile = null
    this.pushTimer = null
    this.previewLabel = "Preview"

    this.handleSliderInput = this.handleSliderInput.bind(this)
    this.handlePreviewClick = this.handlePreviewClick.bind(this)

    this.syncDataset()
    this.bindElements()

    this.setPercent(this.initialPercent(), {emit: false})
  },
  updated() {
    const previousKind = this.previewKind
    const previousSrc = this.previewSrc

    this.syncDataset()
    this.bindElements()
    this.setPercent(this.initialPercent(), {emit: false})

    if (previousKind && previousKind !== this.previewKind) {
      this.stopPreview(true)
    } else if (previousSrc !== this.previewSrc && this.previewKind !== "local-upload") {
      this.stopPreview()
    }
  },
  destroyed() {
    if (this.slider) {
      this.slider.removeEventListener("input", this.handleSliderInput)
    }
    if (this.previewButton) {
      this.previewButton.removeEventListener("click", this.handlePreviewClick)
    }
    if (this.pushTimer) {
      clearTimeout(this.pushTimer)
      this.pushTimer = null
    }
    this.stopPreview(true)
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
    if (this.previewContext) {
      try {
        this.previewContext.close()
      } catch (_err) {}
      this.previewContext = null
    }
  },
  syncDataset() {
    const dataset = this.el.dataset
    const parsedMax = parseInt(dataset.maxPercent || "", 10)
    this.maxPercent =
      Number.isInteger(parsedMax) && parsedMax > 0 ? parsedMax : MAX_VOLUME_PERCENT_DEFAULT
    this.pushEventName = dataset.pushEvent || null
    this.volumeTarget = dataset.volumeTarget || null
    this.previewKind = dataset.previewKind || "existing"
    this.fileInputId = dataset.fileInputId || null
    this.urlInputId = dataset.urlInputId || null
    this.previewSrc = dataset.previewSrc || ""
  },
  bindElements() {
    const slider = this.el.querySelector("[data-role='volume-slider']")
    if (this.slider !== slider) {
      if (this.slider) {
        this.slider.removeEventListener("input", this.handleSliderInput)
      }
      this.slider = slider
      if (this.slider) {
        this.slider.addEventListener("input", this.handleSliderInput)
      }
    }

    const previewButton = this.el.querySelector("[data-role='volume-preview']")
    if (this.previewButton !== previewButton) {
      if (this.previewButton) {
        this.previewButton.removeEventListener("click", this.handlePreviewClick)
      }
      this.previewButton = previewButton
      if (this.previewButton) {
        this.previewButton.addEventListener("click", this.handlePreviewClick)
      }
    }

    if (this.previewButton) {
      this.previewLabel = this.previewButton.textContent?.trim() || this.previewLabel
    }

    this.hiddenInput = this.el.querySelector("[data-role='volume-hidden']")
    this.display = this.el.querySelector("[data-role='volume-display']")
  },
  initialPercent() {
    const hiddenValue = this.hiddenInput?.value
    const sliderValue = this.slider?.value
    return parsePercent(hiddenValue ?? sliderValue ?? this.maxPercent, this.maxPercent, this.maxPercent)
  },
  setPercent(percent, {emit = false} = {}) {
    const bounded = clamp(Math.round(percent), 0, this.maxPercent)
    if (this.slider && Number(this.slider.value) !== bounded) {
      this.slider.value = bounded
    }

    if (this.hiddenInput && Number(this.hiddenInput.value) !== bounded) {
      this.hiddenInput.value = bounded
    }

    if (this.display) {
      this.display.textContent = `${bounded}%`
    }

    if (emit) {
      this.queuePush(bounded)
    }

    this.updatePreviewGain(bounded)
  },
  async handleSliderInput(event) {
    const fallback = this.hiddenInput?.value ?? this.slider?.value ?? this.maxPercent
    const nextPercent = parsePercent(event.target.value, fallback, this.maxPercent)
    event.target.value = nextPercent
    this.setPercent(nextPercent, {emit: true})
  },
  queuePush(percent) {
    if (!this.pushEventName) {
      return
    }

    if (this.pushTimer) {
      clearTimeout(this.pushTimer)
    }

    this.pushTimer = setTimeout(() => {
      const payload = {volume: percent}
      if (this.volumeTarget) {
        payload.target = this.volumeTarget
      }
      this.pushEvent(this.pushEventName, payload)
      this.pushTimer = null
    }, 100)
  },
  async handlePreviewClick(event) {
    event.preventDefault()

    if (this.previewButton && this.previewButton.disabled) {
      return
    }

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

    const percent = parsePercent(
      this.hiddenInput?.value ?? this.slider?.value ?? this.maxPercent,
      this.maxPercent,
      this.maxPercent
    )
    const gain = percentToGain(percent, this.maxPercent)
    await this.ensurePreviewGraph(gain)
    this.applyPreviewGain(gain)

    try {
      await this.previewAudio.play()
      this.setPreviewState(true)
    } catch (error) {
      console.error("Preview playback failed", error)
      this.setPreviewState(false)
    }
  },
  async updatePreviewGain(percent) {
    const gain = percentToGain(percent, this.maxPercent)

    if (!this.previewAudio) {
      return
    }

    await this.ensurePreviewGraph(gain)
    this.applyPreviewGain(gain)
  },
  async ensurePreviewGraph(targetGain) {
    if (!this.previewAudio) {
      return
    }

    const needsBoost = targetGain > 1
    const ContextCtor = getAudioContextCtor()

    if (!needsBoost || !ContextCtor) {
      if (this.previewGain) {
        this.previewGain.gain.value = 1
      }
      return
    }

    if (!this.previewContext) {
      this.previewContext = new ContextCtor()
    }

    if (this.previewContext.state === "suspended") {
      try {
        await this.previewContext.resume()
      } catch (_err) {}
    }

    if (!this.previewSource) {
      try {
        this.previewSource = this.previewContext.createMediaElementSource(this.previewAudio)
      } catch (error) {
        console.warn("Preview gain setup failed", error)
        this.previewSource = null
        this.previewGain = null
        return
      }
    }

    if (!this.previewGain) {
      this.previewGain = this.previewContext.createGain()
      this.previewSource.connect(this.previewGain).connect(this.previewContext.destination)
    }
  },
  applyPreviewGain(targetGain) {
    if (!this.previewAudio) {
      return
    }

    const base = clamp(targetGain, 0, BOOST_CAP)
    const volume = Math.min(base, 1)

    try {
      this.previewAudio.volume = volume
    } catch (_err) {
      this.previewAudio.volume = 1
    }

    if (this.previewGain) {
      this.previewGain.gain.value = base > 1 ? base : 1
    }
  },
  getPreviewSource() {
    if (this.previewKind === "local-upload" && this.fileInputId) {
      const input = document.getElementById(this.fileInputId)
      const file = input && input.files && input.files[0]

      if (!file) {
        return null
      }

      if (this.lastFile !== file) {
        if (this.objectUrl) {
          URL.revokeObjectURL(this.objectUrl)
        }
        this.objectUrl = URL.createObjectURL(file)
        this.lastFile = file
      }

      return this.objectUrl
    }

    if (this.previewKind === "url") {
      if (this.urlInputId) {
        const urlInput = document.getElementById(this.urlInputId)
        const value =
          urlInput && typeof urlInput.value === "string" ? urlInput.value.trim() : ""
        if (value) {
          return value
        }
      }

      return this.previewSrc || null
    }

    return this.previewSrc || null
  },
  stopPreview(forceRevoke = false) {
    if (this.previewAudio) {
      try {
        this.previewAudio.pause()
        this.previewAudio.currentTime = 0
      } catch (_err) {}
      this.previewAudio.src = ""
    }
    this.setPreviewState(false)

    if (forceRevoke && this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
      this.lastFile = null
    }
  },
  setPreviewState(isPlaying) {
    if (!this.previewButton) {
      return
    }

    this.previewButton.textContent = isPlaying ? "Stop Preview" : this.previewLabel
    this.previewButton.dataset.previewState = isPlaying ? "playing" : "stopped"
  }
}

Hooks.VideoPlayer = {
  mounted() {
    this.video = this.el.querySelector("video")
    this.hls = null
    this.currentSessionId = null
    this.currentHlsUrl = null
    this.isHost = false
    this.applyingSync = false
    this.programmaticSeek = false
    this.playbackEventSuppressions = 0
    this.syncToken = 0
    this.wantPlaying = false
    this.isLive = false
    this.syncAnchor = null
    this.syncTimer = setInterval(() => this.correctDrift(), VIDEO_SYNC_INTERVAL_MS)

    this.handleSeeked = () => {
      // Ignore seeks we applied from server sync — those were restarting Discord
      // in a tight loop and made playback laggy.
      if (!this.isHost || this.applyingSync || this.programmaticSeek || !this.video) {
        this.programmaticSeek = false
        return
      }
      // Live Discord follows the upstream stream and cannot seek into its DVR.
      if (this.isLive) {
        // A live Discord stream cannot seek into DVR, so put the browser back
        // beside the audio instead of leaving the two permanently out of sync.
        this.seekToLiveEdge()
        return
      }

      const ms = Math.round(this.video.currentTime * 1000)
      this.pushEvent("video_seek", {ms})
    }

    this.handlePlay = () => {
      if (!this.isHost || this.ignorePlaybackEvent() || this.wantPlaying) return
      this.wantPlaying = true
      this.pushEvent("resume_video", {})
    }

    this.handlePause = () => {
      // A media element emits pause as part of its normal ended sequence. Let
      // the ended event advance the queue instead of first pausing the session
      // and cancelling its server-side completion timer.
      if (this.video?.ended) return
      if (!this.isHost || this.ignorePlaybackEvent() || !this.wantPlaying) return
      this.wantPlaying = false
      this.pushEvent("pause_video", {})
    }

    this.handleEnded = () => {
      if (!this.isHost || this.ignorePlaybackEvent()) return
      const sessionId = this.currentSessionId
      if (!sessionId) return
      this.wantPlaying = false
      this.pushEvent("video_ended", {session_id: sessionId})
    }

    if (this.video) {
      this.video.addEventListener("seeked", this.handleSeeked)
      this.video.addEventListener("play", this.handlePlay)
      this.video.addEventListener("pause", this.handlePause)
      this.video.addEventListener("ended", this.handleEnded)
      this.video.muted = true
      this.video.playsInline = true
    }

    this.handleEvent("video_state", (payload) => this.applyState(payload))
    this.handleEvent("video_sync", (payload) => this.applySync(payload))
    this.handleEvent("video_stop", () => this.teardown())

    this.pushEvent("request_video_state", {})
  },
  destroyed() {
    this.teardown()
    if (this.syncTimer) {
      clearInterval(this.syncTimer)
      this.syncTimer = null
    }
    if (this.video) {
      this.video.removeEventListener("seeked", this.handleSeeked)
      this.video.removeEventListener("play", this.handlePlay)
      this.video.removeEventListener("pause", this.handlePause)
      this.video.removeEventListener("ended", this.handleEnded)
    }
  },
  ignorePlaybackEvent() {
    return this.applyingSync || this.playbackEventSuppressions > 0 || !this.currentSessionId
  },
  withoutPlaybackEvents(action) {
    this.playbackEventSuppressions += 1
    try {
      return action()
    } finally {
      // Media play/pause events are queued by the browser. Release on the next
      // task so those events still see the suppression flag.
      setTimeout(() => {
        this.playbackEventSuppressions = Math.max(0, this.playbackEventSuppressions - 1)
      }, 0)
    }
  },
  applyState(payload) {
    if (!this.video) return

    this.isHost = !!payload.is_host
    this.video.controls = this.isHost
    this.video.muted = true
    this.isLive = payload.live === true || payload.live === "true"

    if (!payload.hls_url || payload.status !== "ready") {
      if (!payload.hls_url) this.teardownMedia()
      return
    }

    const sessionChanged =
      this.currentSessionId !== payload.session_id || this.currentHlsUrl !== payload.hls_url
    if (sessionChanged) {
      this.attachHls(payload.hls_url, payload.session_id)
    }

    this.applySync(payload, {forceSeek: sessionChanged})
  },
  applySync(payload, opts = {}) {
    if (!this.video || payload == null) return

    const live = payload.live === true || payload.live === "true"
    const positionMs = Number(payload.position_ms)
    const playing = payload.playing === true || payload.playing === "true"
    const wasPlaying = this.wantPlaying
    const token = ++this.syncToken
    this.isLive = live
    this.wantPlaying = playing

    if (!live && Number.isFinite(positionMs)) {
      this.syncAnchor = {
        positionSec: positionMs / 1000,
        observedAt: performance.now(),
        playing
      }
    } else {
      this.syncAnchor = null
    }

    this.applyingSync = true

    // Snap when starting/resuming, attaching, or while the media is still
    // loading. A newer sync event must replace any stale metadata callback.
    const shouldSeek = opts.forceSeek || (playing && (!wasPlaying || this.video.readyState < 2))
    if (shouldSeek) {
      if (live) {
        this.seekToLiveEdge(token)
      } else if (Number.isFinite(positionMs)) {
        this.seekToMs(positionMs, token)
      }
    }

    const finish = () => {
      if (token !== this.syncToken) return
      this.applyingSync = false
    }

    if (playing) {
      const playPromise = this.withoutPlaybackEvents(() => this.video.play())
      if (playPromise && typeof playPromise.finally === "function") {
        playPromise.catch(() => {}).finally(finish)
      } else if (playPromise && playPromise.catch) {
        playPromise.catch(() => {}).then(finish)
      } else {
        setTimeout(finish, 250)
      }
    } else {
      this.withoutPlaybackEvents(() => this.video.pause())
      this.video.playbackRate = 1
      setTimeout(finish, 100)
    }
  },
  targetPosition(fallbackPositionSec = null) {
    if (!this.syncAnchor) return fallbackPositionSec

    const elapsed = this.syncAnchor.playing
      ? Math.max(0, performance.now() - this.syncAnchor.observedAt) / 1000
      : 0

    let target = this.syncAnchor.positionSec + elapsed
    if (Number.isFinite(this.video?.duration)) {
      target = Math.min(target, this.video.duration)
    }
    return Math.max(0, target)
  },
  liveTargetPosition() {
    if (!this.video) return null
    const Hls = HlsCtor()

    if (this.hls && Hls && Number.isFinite(this.hls.liveSyncPosition)) {
      return this.hls.liveSyncPosition - LIVE_AV_OFFSET_SEC
    }

    try {
      if (this.video.seekable?.length > 0) {
        return this.video.seekable.end(this.video.seekable.length - 1) - (1.5 + LIVE_AV_OFFSET_SEC)
      }
    } catch (_err) {
      return null
    }

    return null
  },
  clampToSeekable(target) {
    if (!this.video || !Number.isFinite(target)) return target

    try {
      if (this.video.seekable?.length > 0) {
        const range = this.video.seekable.length - 1
        return Math.min(Math.max(target, this.video.seekable.start(range)), this.video.seekable.end(range))
      }
    } catch (_err) {
      return target
    }

    return target
  },
  correctDrift() {
    if (!this.video || !this.wantPlaying || this.video.readyState < 2 || this.video.seeking) return

    const target = this.isLive ? this.liveTargetPosition() : this.targetPosition()
    if (!Number.isFinite(target)) return

    const drift = this.clampToSeekable(target) - this.video.currentTime
    if (Math.abs(drift) >= VIDEO_HARD_DRIFT_SEC) {
      try {
        this.programmaticSeek = true
        this.video.currentTime = this.clampToSeekable(target)
        this.video.playbackRate = 1
      } catch (_err) {
        this.programmaticSeek = false
      }
      return
    }

    if (this.isLive || Math.abs(drift) <= VIDEO_SOFT_DRIFT_SEC) {
      this.video.playbackRate = 1
      return
    }

    // Small corrections are less distracting as a temporary speed adjustment.
    this.video.playbackRate = 1 + clamp(
      drift * 0.12,
      -VIDEO_MAX_RATE_ADJUSTMENT,
      VIDEO_MAX_RATE_ADJUSTMENT
    )
  },
  seekToLiveEdge(token = this.syncToken) {
    if (!this.video) return

    const apply = () => {
      if (!this.video || token !== this.syncToken) return

      try {
        const target = this.liveTargetPosition()

        if (target == null) return

        this.programmaticSeek = true
        this.video.currentTime = this.clampToSeekable(target)
      } catch (_err) {
        this.programmaticSeek = false
      }
    }

    const Hls = HlsCtor()
    if (this.hls && Hls?.Events?.LEVEL_LOADED) {
      this.hls.once(Hls.Events.LEVEL_LOADED, apply)
      apply()
    } else if (this.video.readyState >= 1) {
      apply()
    } else {
      this.video.addEventListener("loadedmetadata", apply, {once: true})
    }
  },
  seekToMs(positionMs, token = this.syncToken) {
    if (!this.video || !Number.isFinite(positionMs)) return

    const apply = () => {
      if (!this.video || token !== this.syncToken) return
      const target = this.targetPosition(positionMs / 1000)
      const drift = Math.abs(this.video.currentTime - target)
      if (drift <= VIDEO_SOFT_DRIFT_SEC) return

      try {
        this.programmaticSeek = true
        this.video.currentTime = target
      } catch (_err) {
        this.programmaticSeek = false
      }
    }

    if (this.video.readyState >= 1) {
      apply()
    } else {
      this.video.addEventListener("loadedmetadata", apply, {once: true})
    }
  },
  attachHls(url, sessionId) {
    this.teardownMedia()
    this.currentSessionId = sessionId
    this.currentHlsUrl = url
    const Hls = HlsCtor()

    if (this.video.canPlayType("application/vnd.apple.mpegurl")) {
      this.video.src = url
      return
    }

    if (Hls && Hls.isSupported()) {
      // Hold ~2 segments behind the remux edge, then seekToLiveEdge applies an
      // extra LIVE_AV_OFFSET_SEC so video waits for Discord audio.
      this.hls = new Hls({
        enableWorker: true,
        liveSyncDurationCount: 3,
        liveMaxLatencyDurationCount: 6,
        liveDurationInfinity: true,
        // Don't speed up to chase the live edge — that pulls video ahead of Discord.
        maxLiveSyncPlaybackRate: 1,
        xhrSetup: (xhr) => {
          xhr.withCredentials = true
        }
      })
      this.hls.on(Hls.Events.ERROR, (_event, data) => {
        if (data?.fatal) {
          console.error("HLS fatal error", data)
          if (data.type === Hls.ErrorTypes.NETWORK_ERROR) this.hls.startLoad()
          if (data.type === Hls.ErrorTypes.MEDIA_ERROR) this.hls.recoverMediaError()
        }
      })
      this.hls.on(Hls.Events.MANIFEST_PARSED, () => {
        if (!this.video) return
        if (this.wantPlaying) {
          if (this.isLive) {
            this.seekToLiveEdge()
          } else if (this.syncAnchor) {
            this.seekToMs(this.syncAnchor.positionSec * 1000)
          }
          const playPromise = this.withoutPlaybackEvents(() => this.video.play())
          if (playPromise && playPromise.catch) playPromise.catch(() => {})
        }
      })
      this.hls.loadSource(url)
      this.hls.attachMedia(this.video)
      return
    }

    console.error("HLS.js is unavailable; cannot play video in this browser")
  },
  teardownMedia() {
    if (this.hls) {
      this.hls.destroy()
      this.hls = null
    }
    if (this.video) {
      this.withoutPlaybackEvents(() => {
        this.video.removeAttribute("src")
        this.video.load()
      })
    }
    this.currentSessionId = null
    this.currentHlsUrl = null
    this.syncAnchor = null
    if (this.video) this.video.playbackRate = 1
  },
  teardown() {
    this.teardownMedia()
    this.wantPlaying = false
    this.isLive = false
  }
}

Hooks.CopyButton = {
  mounted() {
    this.handleClick = async (e) => {
      e.preventDefault()
      const original = this.el.textContent
      const text =
        this.el.dataset.copyText ||
        this.el.getAttribute("data-copy-text") ||
        (this.el.nextElementSibling ? this.el.nextElementSibling.innerText : "")
      try {
        if (navigator.clipboard && window.isSecureContext) {
          await navigator.clipboard.writeText(text)
        } else {
          // Fallback for insecure contexts
          const ta = document.createElement("textarea")
          ta.value = text
          ta.style.position = "fixed"
          ta.style.opacity = "0"
          document.body.appendChild(ta)
          ta.select()
          document.execCommand("copy")
          document.body.removeChild(ta)
        }
        this.el.textContent = "Copied!"
        this.el.classList.add("text-green-600")
        setTimeout(() => {
          this.el.textContent = original
          this.el.classList.remove("text-green-600")
        }, 1500)
      } catch (_err) {
        this.el.textContent = "Copy failed"
        this.el.classList.add("text-red-600")
        setTimeout(() => {
          this.el.textContent = original
          this.el.classList.remove("text-red-600")
        }, 1500)
      }
    }
    this.el.addEventListener("click", this.handleClick)
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick)
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300))
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

if (window.navigator.standalone) {
  document.documentElement.style.setProperty("--sat", "env(safe-area-inset-top)")
  document.documentElement.classList.add("standalone")
}
