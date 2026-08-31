import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "ecloaiza.blueiris"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var cameras: service ? service.cameras : []
  readonly property string statusText: service ? service.statusText : "Connecting…"
  readonly property bool needsLogin: service ? service.needsLogin === true : false
  property bool signedIn: false
  property bool showSettings: false
  readonly property int stillRevision: service ? Number(service.stillRevision || 0) : 0
  readonly property int tileWidth: Style.space(168)
  readonly property int tileHeight: Style.space(96)

  function open() {
    if (root.service) {
      root.service.panelOpen = true
      root.service.clearUnread()
    }
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.service) root.service.panelOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function saveConnection() {
    if (!root.service) return
    root.service.persistSettings({
      url: urlField.text,
      username: userField.text
    })
    root.service.persistPassword(passField.text)
    root.service.session = ""
    root.service.connected = false
    root.service.signedIn = false
    root.signedIn = false
    root.service.statusText = "Connecting…"
    Qt.callLater(function() { if (root.service) root.service.tick() })
  }

  function saveRefresh() {
    if (!root.service) return
    var n = Math.max(1, parseInt(refreshField.text, 10) || 5)
    refreshField.text = String(n)
    root.service.persistSettings({ refreshSeconds: n })
  }

  function logout() {
    if (root.service) root.service.logout()
    root.signedIn = false
    root.showSettings = false
    passField.text = ""
    userField.text = ""
  }

  function syncAuth() {
    root.signedIn = !!(root.service && root.service.signedIn)
    if (!root.service) return
    if (!urlField.activeFocus) urlField.text = root.service.url
    if (!userField.activeFocus) userField.text = root.service.username
    if (!passField.activeFocus) passField.text = root.service.password
    if (!refreshField.activeFocus) refreshField.text = String(root.service.refreshSeconds)
  }

  onServiceChanged: root.syncAuth()

  Connections {
    target: root.service
    function onSignedInChanged() { root.syncAuth() }
    function onConnectedChanged() { root.syncAuth() }
    function onStatusTextChanged() { root.syncAuth() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: urlField.activeFocus || userField.activeFocus || passField.activeFocus || refreshField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: content
        width: panelFlick.width
        spacing: Style.space(10)

        Item {
          width: parent.width
          height: Math.max(titleLabel.implicitHeight, headerActions.implicitHeight)

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            CameraIcon {
              iconSize: Style.font.subtitle
              color: root.contentForeground
            }

            Text {
              id: titleLabel
              text: "omaBlueIris"
              elide: Text.ElideRight
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              visible: root.signedIn
              iconText: "󰒓"
              tooltipText: root.showSettings ? "Back to cameras" : "Settings"
              foreground: root.showSettings ? Color.accent : root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.showSettings = !root.showSettings
            }

            PanelActionButton {
              iconText: "󰖟"
              tooltipText: "Open Blue Iris"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: if (root.service) root.service.openInBrowser()
            }

            PanelActionButton {
              visible: root.signedIn
              iconText: "󰍃"
              tooltipText: "Log out"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.logout()
            }
          }
        }

        Text {
          width: parent.width
          text: root.statusText
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(8)
          visible: root.cameras.length > 0 && !root.showSettings

          Repeater {
            model: root.cameras

            CursorSurface {
              id: tile
              required property var modelData
              width: root.tileWidth
              implicitHeight: tileContent.implicitHeight + Style.space(12)
              hasCursor: tileMouse.containsMouse
              foreground: root.contentForeground
              accent: Color.accent

              Column {
                id: tileContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(6)
                spacing: Style.space(4)

                Image {
                  width: parent.width
                  height: root.tileHeight
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  retainWhileLoading: true
                  source: root.service
                    ? "file://" + root.service.stillPath(tile.modelData.name) + "?" + root.stillRevision
                    : ""
                }

                Text {
                  width: parent.width
                  text: tile.modelData.displayName
                  elide: Text.ElideRight
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  visible: !tile.modelData.isOnline
                  width: parent.width
                  text: "offline"
                  elide: Text.ElideRight
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.italic: true
                }
              }

              MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.service) root.service.openLive(tile.modelData.name)
                  root.close()
                }
              }
            }
          }
        }

        Text {
          visible: root.cameras.length === 0 && !root.showSettings
          width: parent.width
          text: root.needsLogin ? "Sign in to load cameras." : "No cameras yet."
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.signedIn && root.showSettings
          height: visible ? implicitHeight : 0

          PanelSectionHeader {
            text: "DISPLAY"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Toggle {
            width: parent.width
            label: "4:3 aspect ratio"
            description: "Use 4:3 instead of 16:9 for live camera windows"
            checked: !!(root.service && root.service.aspectRatio === "4:3")
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: if (root.service)
              root.service.persistSettings({ aspectRatio: root.service.aspectRatio === "4:3" ? "16:9" : "4:3" })
          }

          Text {
            width: parent.width
            text: "Still refresh (seconds)"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            id: refreshField
            width: parent.width
            placeholderText: "5"
            foreground: root.contentForeground
            onEditingFinished: root.saveRefresh()
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: !root.signedIn
          height: visible ? implicitHeight : 0

          TextField {
            id: urlField
            width: parent.width
            placeholderText: "http://192.168.1.100:81"
          }

          TextField {
            id: userField
            width: parent.width
            placeholderText: "username"
          }

          TextField {
            id: passField
            width: parent.width
            password: true
            placeholderText: "password"
          }

          Button {
            text: "Save"
            foreground: root.contentForeground
            onClicked: root.saveConnection()
          }
        }
      }
      }
    }
  }
}
