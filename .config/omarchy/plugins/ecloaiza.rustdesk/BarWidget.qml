import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// RustDesk's Flutter Linux build never registers a StatusNotifierItem, so it
// cannot show up in ecloaiza.tray (or any real tray) no matter what runs.
// This stands in for that: an always-visible icon that launches RustDesk,
// focuses its window if one is already open, and closes it on middle/right
// click. Not a real tray icon (no menu, no app-pushed status) - just enough
// to click to get to RustDesk without hunting for its window.
BarWidget {
  id: root
  moduleName: "ecloaiza.rustdesk"

  readonly property string appId: "rustdesk"

  readonly property var toplevel: {
    var list = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].appId || "").toLowerCase() === root.appId) return list[i]
    }
    return null
  }
  readonly property bool running: toplevel !== null

  visible: true
  implicitWidth: root.vertical ? root.barSize : Style.bar.iconSlot
  implicitHeight: root.vertical ? Style.bar.iconSlot : root.barSize

  function launch() {
    Util.execDetached("uwsm-app -- gtk-launch rustdesk.desktop")
  }

  function activate() {
    if (root.toplevel) root.toplevel.activate()
    else root.launch()
  }

  Image {
    id: icon
    anchors.centerIn: parent
    width: Style.space(12)
    height: Style.space(12)
    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
    source: Quickshell.iconPath("rustdesk", true)
    opacity: root.running ? 1.0 : 0.55

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, root.running ? "RustDesk (running)" : "RustDesk")
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) {
      if (root.bar) root.bar.hideTooltip(root)
      if (mouse.button === Qt.MiddleButton || mouse.button === Qt.RightButton) {
        if (root.toplevel) root.toplevel.close()
      } else {
        root.activate()
      }
    }
  }
}
