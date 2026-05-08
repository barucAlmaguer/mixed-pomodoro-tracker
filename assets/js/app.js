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
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pomodoro_tracker"
import topbar from "../vendor/topbar"

const Hooks = {
  TimelineRangePicker: {
    mounted() {
      this.surface = this.el.querySelector("[data-role='surface']")
      this.tooltip = this.el.querySelector("[data-role='tooltip']")
      this.selection = this.el.querySelector("[data-role='selection']")
      this.dragging = false
      this.anchorMinute = null

      this.onMouseDown = (event) => {
        if (event.button !== 0) return
        this.dragging = true
        this.anchorMinute = this.minuteFromClientX(event.clientX)
        const previewEnd = Math.min(this.endMinute(), this.anchorMinute + this.stepMinute())
        this.renderSelection(this.anchorMinute, previewEnd)
        this.renderTooltip(event.clientX, this.rangeLabel(this.anchorMinute, previewEnd))
        window.addEventListener("mousemove", this.onWindowMouseMove)
        window.addEventListener("mouseup", this.onWindowMouseUp)
        event.preventDefault()
      }

      this.onMouseMove = (event) => {
        if (this.dragging) return
        const minute = this.minuteFromClientX(event.clientX)
        this.clearSelection()
        this.renderTooltip(event.clientX, this.minuteLabel(minute))
      }

      this.onMouseLeave = () => {
        if (!this.dragging) {
          this.hideTooltip()
          this.clearSelection()
        }
      }

      this.onWindowMouseMove = (event) => {
        if (!this.dragging) return
        const minute = this.minuteFromClientX(event.clientX)
        const [startMinute, endMinute] = this.sortedRange(this.anchorMinute, minute)
        this.renderSelection(startMinute, endMinute)
        this.renderTooltip(event.clientX, this.rangeLabel(startMinute, endMinute))
      }

      this.onWindowMouseUp = (event) => {
        if (!this.dragging) return
        this.dragging = false
        window.removeEventListener("mousemove", this.onWindowMouseMove)
        window.removeEventListener("mouseup", this.onWindowMouseUp)

        const minute = this.minuteFromClientX(event.clientX)
        let [startMinute, endMinute] = this.sortedRange(this.anchorMinute, minute)

        if (startMinute === endMinute) {
          endMinute = Math.min(this.endMinute(), startMinute + this.stepMinute())
        }

        this.renderSelection(startMinute, endMinute)
        this.pushEvent("timeline:range_selected", {
          start_minute: startMinute,
          end_minute: endMinute
        })
      }

      this.surface.addEventListener("mousedown", this.onMouseDown)
      this.surface.addEventListener("mousemove", this.onMouseMove)
      this.surface.addEventListener("mouseleave", this.onMouseLeave)
    },

    destroyed() {
      this.surface?.removeEventListener("mousedown", this.onMouseDown)
      this.surface?.removeEventListener("mousemove", this.onMouseMove)
      this.surface?.removeEventListener("mouseleave", this.onMouseLeave)
      window.removeEventListener("mousemove", this.onWindowMouseMove)
      window.removeEventListener("mouseup", this.onWindowMouseUp)
    },

    startMinute() {
      return parseInt(this.el.dataset.startMinute || "420", 10)
    },

    endMinute() {
      return parseInt(this.el.dataset.endMinute || "1200", 10)
    },

    stepMinute() {
      return parseInt(this.el.dataset.stepMinute || "10", 10)
    },

    minuteFromClientX(clientX) {
      const rect = this.surface.getBoundingClientRect()
      const clampedX = Math.max(rect.left, Math.min(clientX, rect.right))
      const ratio = rect.width === 0 ? 0 : (clampedX - rect.left) / rect.width
      const raw = this.startMinute() + ratio * (this.endMinute() - this.startMinute())
      const stepped = Math.round(raw / this.stepMinute()) * this.stepMinute()
      return Math.max(this.startMinute(), Math.min(stepped, this.endMinute()))
    },

    sortedRange(a, b) {
      return [Math.min(a, b), Math.max(a, b)]
    },

    renderSelection(startMinute, endMinute) {
      if (!this.selection) return

      startMinute = Math.max(this.startMinute(), Math.min(startMinute, this.endMinute()))
      endMinute = Math.max(this.startMinute(), Math.min(endMinute, this.endMinute()))

      const startPct = (startMinute - this.startMinute()) / (this.endMinute() - this.startMinute()) * 100
      const endPct = (endMinute - this.startMinute()) / (this.endMinute() - this.startMinute()) * 100

      this.selection.style.left = `${startPct}%`
      this.selection.style.width = `${Math.max(endPct - startPct, 0)}%`
      this.selection.classList.remove("hidden")
    },

    clearSelection() {
      this.selection?.classList.add("hidden")
    },

    renderTooltip(clientX, text) {
      if (!this.tooltip) return
      const rect = this.surface.getBoundingClientRect()
      const left = Math.max(12, Math.min(clientX - rect.left, rect.width - 12))
      this.tooltip.textContent = text
      this.tooltip.style.left = `${left}px`
      this.tooltip.classList.remove("hidden")
    },

    hideTooltip() {
      this.tooltip?.classList.add("hidden")
    },

    rangeLabel(startMinute, endMinute) {
      return `${this.minuteLabel(startMinute)} → ${this.minuteLabel(endMinute)}`
    },

    minuteLabel(totalMinutes) {
      const hours24 = Math.floor(totalMinutes / 60)
      const minutes = totalMinutes % 60
      const period = hours24 >= 12 ? "pm" : "am"
      const hour12 = hours24 % 12 === 0 ? 12 : hours24 % 12
      return `${hour12}:${String(minutes).padStart(2, "0")}${period}`
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
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

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
