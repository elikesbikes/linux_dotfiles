import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// World clock bar label, à la sindresorhus.com/zone-bar. Just Tokyo for now;
// more zones can be added as additional widget instances later. Shells out to
// `date` with TZ set rather than QML's Date/Intl so DST is handled for free,
// and shows a +1/-1 day marker when the zone's calendar day differs from ours.
BarWidget {
  id: root
  moduleName: "ecloaiza.zone"

  readonly property string zoneTz: "Asia/Tokyo"
  readonly property string zoneEmoji: "🗼"

  property string displayText: zoneEmoji + " --:--"
  property string tooltip: "Tokyo"

  function applyStatus(text) {
    var parts = String(text || "").trim().split("|")
    if (parts.length < 2) return
    root.displayText = root.zoneEmoji + " " + parts[0]
    root.tooltip = parts[1]
  }

  function refresh() {
    if (!queryProc.running) queryProc.running = true
  }

  Process {
    id: queryProc
    command: ["bash", "-lc", `
      tz="` + root.zoneTz + `"
      t=$(TZ="$tz" date +%H:%M)
      zd=$(TZ="$tz" date +%Y-%m-%d)
      ld=$(date +%Y-%m-%d)
      day=""
      if [[ "$zd" > "$ld" ]]; then day=" +1"; elif [[ "$zd" < "$ld" ]]; then day=" -1"; fi
      tt=$(TZ="$tz" date "+Tokyo - %A, %B %-d, UTC%z")
      printf '%s|%s\\n' "$t$day" "$tt"
    `]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    tooltipText: root.tooltip
    horizontalMargin: 8.75
    verticalPadding: 8.75
  }
}
