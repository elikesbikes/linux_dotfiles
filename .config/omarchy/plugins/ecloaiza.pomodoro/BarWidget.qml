import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "State.js" as S

BarWidget {
  id: root
  moduleName: "ecloaiza.pomodoro"

  readonly property var focusPresets: S.focusPresets
  property int focusIndex: S.focusIndex
  property int lapLength: S.lapLength
  readonly property int shortBreak: S.shortBreak
  readonly property int longBreak: S.longBreak
  readonly property int lapsUntilLong: S.lapsUntilLong

  property string phase: S.phase
  property int completedLaps: S.completedLaps
  property bool running: S.running
  property int remaining: S.remaining
  property real deadline: S.deadline
  property bool showingPreset: false

  readonly property bool onBreak: phase === "short" || phase === "long"

  Component.onCompleted: {
    S.init({
      lapLength: setting("lapLength", 25),
      shortBreak: setting("shortBreak", 5),
      longBreak: setting("longBreak", 15),
      lapsUntilLong: setting("lapsUntilLong", 4)
    })
    pullState()
  }

  function pullState() {
    root.focusIndex = S.focusIndex
    root.lapLength = S.lapLength
    root.phase = S.phase
    root.completedLaps = S.completedLaps
    root.running = S.running
    root.remaining = S.remaining
    root.deadline = S.deadline
  }

  function pushAndBroadcast() {
    broadcast("pullState")
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
    if (S.phase === "idle") {
      S.phase = "work"
      S.remaining = S.minutesFor("work") * 60
    }
    S.running = true
    S.deadline = Date.now() / 1000 + S.remaining
    pushAndBroadcast()
  }

  function pause() {
    if (S.running)
      S.remaining = Math.max(0, Math.round(S.deadline - Date.now() / 1000))
    S.running = false
    pushAndBroadcast()
  }

  function advance() {
    var next
    if (S.phase === "work") {
      S.completedLaps += 1
      next = (S.completedLaps % S.lapsUntilLong === 0) ? "long" : "short"
    } else {
      next = "work"
    }
    S.phase = next
    S.remaining = S.minutesFor(next) * 60
    if (S.running)
      S.deadline = Date.now() / 1000 + S.remaining
    pushAndBroadcast()
    playAlert()
  }

  function cycleFocusPreset() {
    S.focusIndex = (S.focusIndex + 1) % S.focusPresets.length
    S.lapLength = S.focusPresets[S.focusIndex]
    if (S.phase === "idle")
      S.remaining = S.lapLength * 60
    pushAndBroadcast()
    root.showingPreset = true
    presetTimer.restart()
  }

  function reset() {
    S.running = false
    S.phase = "idle"
    S.completedLaps = 0
    S.remaining = S.minutesFor("work") * 60
    pushAndBroadcast()
  }

  function tick() {
    if (!S.running) return
    var rem = Math.max(0, Math.round(S.deadline - Date.now() / 1000))
    S.remaining = rem
    if (rem <= 0) {
      advance()
      return
    }
    pullState()
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

    active: root.running && !root.onBreak
    dimmed: !root.running

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFocusPreset()
      else if (b === Qt.MiddleButton) root.phase === "idle" ? root.reset() : root.advance()
      else root.running ? root.pause() : root.start()
    }
  }
}
