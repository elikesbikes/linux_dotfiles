import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Pomodoro countdown for the bar.
//
// Left click starts or pauses, right click cycles focus duration presets
// (shown briefly in the bar), middle click skips to next phase, middle
// click while idle resets.
BarWidget {
  id: root
  moduleName: "ecloaiza.pomodoro"

  readonly property var focusPresets: [5, 10, 15, 20, 25, 30, 45, 50, 60, 90]
  property int focusIndex: Math.max(0, focusPresets.indexOf(setting("lapLength", 25)))
  property int lapLength: focusPresets[focusIndex]
  readonly property int shortBreak: setting("shortBreak", 5)
  readonly property int longBreak: setting("longBreak", 15)
  readonly property int lapsUntilLong: Math.max(1, setting("lapsUntilLong", 4))

  property string phase: "idle"
  property int completedLaps: 0
  property bool running: false
  property int remaining: root.lapLength * 60
  property real deadline: 0
  property bool showingPreset: false

  readonly property bool onBreak: phase === "short" || phase === "long"

  function minutesFor(which) {
    if (which === "short") return root.shortBreak
    if (which === "long") return root.longBreak
    return root.lapLength
  }

  readonly property string clockText: {
    var m = Math.floor(root.remaining / 60)
    var s = root.remaining % 60
    return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
  }

  readonly property string displayText: {
    if (root.showingPreset) return root.lapLength + "m"
    return (root.onBreak ? "Break " : "") + root.clockText
  }

  function playAlert() {
    Quickshell.execDetached(["bash", "-lc", "paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"])
  }

  function start() {
    if (root.phase === "idle") {
      root.phase = "work"
      root.remaining = root.minutesFor("work") * 60
    }
    root.running = true
    root.deadline = Date.now() / 1000 + root.remaining
  }

  function pause() {
    if (root.running)
      root.remaining = Math.max(0, Math.round(root.deadline - Date.now() / 1000))
    root.running = false
  }

  function advance() {
    var next
    if (root.phase === "work") {
      root.completedLaps += 1
      next = (root.completedLaps % root.lapsUntilLong === 0) ? "long" : "short"
    } else {
      next = "work"
    }
    root.phase = next
    root.remaining = root.minutesFor(next) * 60
    if (root.running)
      root.deadline = Date.now() / 1000 + root.remaining
    root.playAlert()
  }

  function cycleFocusPreset() {
    root.focusIndex = (root.focusIndex + 1) % root.focusPresets.length
    root.lapLength = root.focusPresets[root.focusIndex]
    if (root.phase === "idle")
      root.remaining = root.lapLength * 60
    root.showingPreset = true
    presetTimer.restart()
  }

  function reset() {
    root.running = false
    root.phase = "idle"
    root.completedLaps = 0
    root.remaining = root.minutesFor("work") * 60
  }

  function tick() {
    if (!root.running) return
    var rem = Math.max(0, Math.round(root.deadline - Date.now() / 1000))
    root.remaining = rem
    if (rem <= 0) root.advance()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.tick()
  }

  Timer {
    id: presetTimer
    interval: 2000
    onTriggered: root.showingPreset = false
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: text !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75

    // Accent while focusing; dimmed whenever the clock is not counting down.
    active: root.running && !root.onBreak
    dimmed: !root.running

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFocusPreset()
      else if (b === Qt.MiddleButton) root.phase === "idle" ? root.reset() : root.advance()
      else root.running ? root.pause() : root.start()
    }
  }
}
