import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Pomodoro countdown for the bar.
//
// Left click starts or pauses, right click skips to the next phase, middle
// click resets. Colour comes from the bar's own tokens rather than fixed
// hexes, so the widget follows whatever theme is active.
BarWidget {
  id: root
  moduleName: "ecloaiza.pomodoro"

  readonly property int lapLength: setting("lapLength", 25)
  readonly property int shortBreak: setting("shortBreak", 5)
  readonly property int longBreak: setting("longBreak", 15)
  readonly property int lapsUntilLong: Math.max(1, setting("lapsUntilLong", 4))

  property string phase: "idle"
  property int completedLaps: 0
  property bool running: false
  property int remaining: root.lapLength * 60
  property real deadline: 0

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

  readonly property string displayText: (root.onBreak ? "Break " : "") + root.clockText

  function start() {
    if (root.phase === "idle") {
      root.phase = "work"
      root.remaining = root.minutesFor("work") * 60
    }
    root.running = true
    // Anchor to a wall-clock deadline so the countdown cannot drift.
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
      if (b === Qt.RightButton) root.advance()
      else if (b === Qt.MiddleButton) root.reset()
      else root.running ? root.pause() : root.start()
    }
  }
}
