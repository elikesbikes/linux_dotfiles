import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Proton Drive has no background sync daemon to poll -- proton-drive-cli is
// one-shot -- so this is a launcher menu (login state + quick actions)
// rather than a live status widget.
BarWidget {
  id: root
  moduleName: "ecloaiza.proton-drive"

  property bool loggedIn: false
  property bool menuOpen: false

  function refreshAuth() {
    if (!authCheckProc.running) authCheckProc.running = true
  }

  function scheduleRefresh() {
    refreshDelayTimer.restart()
  }

  function launchInTerminal(innerCommand) {
    if (!root.bar) return
    root.bar.run("omarchy-launch-floating-terminal-with-presentation '" + innerCommand + "'")
  }

  function login() {
    root.menuOpen = false
    launchInTerminal("proton-drive auth login")
    scheduleRefresh()
  }

  function logout() {
    root.menuOpen = false
    if (root.bar) root.bar.run("proton-drive auth logout")
    scheduleRefresh()
  }

  function listFiles() {
    root.menuOpen = false
    launchInTerminal("proton-drive filesystem list /my-files; exec bash")
  }

  function uploadHint() {
    root.menuOpen = false
    launchInTerminal("echo Usage: proton-drive filesystem upload LOCALPATH REMOTEPARENT; echo Example: proton-drive fs up ~/photo.png /my-files; exec bash")
  }

  function openWeb() {
    root.menuOpen = false
    if (root.bar) root.bar.run("xdg-open https://drive.proton.me")
  }

  Process {
    id: authCheckProc
    command: ["bash", "-lc", "timeout 8 proton-drive filesystem info /my-files >/dev/null 2>&1"]
    onExited: function(exitCode) { root.loggedIn = exitCode === 0 }
  }

  Timer {
    id: refreshDelayTimer
    interval: 4000
    repeat: false
    onTriggered: root.refreshAuth()
  }

  Timer {
    interval: 600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAuth()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: root.loggedIn ? "Proton Drive" : "Proton Drive (not signed in)"
    onPressed: root.menuOpen = !root.menuOpen
  }

  PopupCard {
    id: menuPopup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.menuOpen
    contentWidth: menuPopup.fittedContentWidth(Style.space(220))
    contentHeight: menuPopup.fittedContentHeight(menuColumn.implicitHeight)

    Column {
      id: menuColumn
      anchors.fill: parent
      spacing: Style.space(4)

      Text {
        text: "Proton Drive"
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        text: root.loggedIn ? "Signed in" : "Not signed in"
        color: Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Item { width: 1; height: Style.space(4) }

      Button {
        visible: !root.loggedIn
        width: menuColumn.width
        leftAlign: true
        iconText: ""
        text: "Sign in"
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        onClicked: root.login()
      }

      Button {
        visible: root.loggedIn
        width: menuColumn.width
        leftAlign: true
        iconText: ""
        text: "Sign out"
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        onClicked: root.logout()
      }

      Button {
        visible: root.loggedIn
        width: menuColumn.width
        leftAlign: true
        iconText: ""
        text: "List my files"
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        onClicked: root.listFiles()
      }

      Button {
        visible: root.loggedIn
        width: menuColumn.width
        leftAlign: true
        iconText: ""
        text: "Upload..."
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        onClicked: root.uploadHint()
      }

      Button {
        width: menuColumn.width
        leftAlign: true
        iconText: ""
        text: "Open drive.proton.me"
        foreground: root.bar ? root.bar.barForeground : Color.foreground
        onClicked: root.openWeb()
      }
    }
  }
}
