import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var cameras: []
  property bool connected: false
  property bool needsLogin: false
  property bool signedIn: false
  property string statusText: "Connecting…"
  property string session: ""
  property string password: ""
  property int unreadCount: 0
  property int stillRevision: 0
  property bool panelOpen: false
  property int liveCount: 0
  property string apiKind: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"
  readonly property string cacheDir: home + "/.cache/omarchy/blueiris"
  readonly property string passwordPath: stateDir + "/blueiris.json"
  readonly property string apiBodyPath: cacheDir + "/api-body.json"
  readonly property var pluginSettings: Model.pluginSettings(shell ? shell.shellConfig : null, Model.PLUGIN_ID)
  readonly property string url: pluginSettings.url
  readonly property string username: pluginSettings.username
  readonly property int refreshSeconds: pluginSettings.refreshSeconds
  readonly property string aspectRatio: pluginSettings.aspectRatio

  function stillPath(camera) {
    return cacheDir + "/" + String(camera || "").replace(/[^A-Za-z0-9._-]/g, "_") + ".jpg"
  }

  function persistSettings(values) {
    var entry = {
      id: Model.PLUGIN_ID,
      url: root.url,
      username: root.username,
      refreshSeconds: root.refreshSeconds,
      aspectRatio: root.aspectRatio
    }
    for (var key in values) entry[key] = values[key]
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(Model.PLUGIN_ID, entry)
  }

  function persistPassword(value) {
    root.password = String(value || "")
    passwordFile.setText(Model.serializePasswordFile(root.password))
    chmodProc.command = ["chmod", "600", passwordPath]
    chmodProc.running = true
  }

  function logout() {
    root.session = ""
    root.connected = false
    root.signedIn = false
    root.needsLogin = true
    root.cameras = []
    root.statusText = "Signed out"
    if (stillsProc.running) stillsProc.running = false
    persistSettings({ username: "" })
    persistPassword("")
    closeLive()
    ensureCacheProc.command = ["bash", "-c", "rm -f \"$1\"/*.jpg", "--", cacheDir]
    ensureCacheProc.running = true
    root.stillRevision += 1
  }

  function openInBrowser() {
    if (!root.url) return
    openProc.command = ["omarchy", "launch", "browser", root.url]
    openProc.running = true
  }

  function openLive(camera) {
    var name = String(camera || "")
    if (!name || !root.url) return
    var streamUrl = Model.mjpegUrl(root.url, name)
    if (root.session) streamUrl += (streamUrl.indexOf("?") !== -1 ? "&" : "?") + "session=" + root.session
    var geometry = Model.liveGeometry(root.liveCount, root.aspectRatio)
    root.liveCount += 1
    liveModel.append({
      name: name,
      mediaUrl: streamUrl,
      title: "omaBlueIris – " + name,
      geometry: geometry
    })
  }

  function dropLive(name) {
    for (var i = 0; i < liveModel.count; i++) {
      if (liveModel.get(i).name === name) {
        liveModel.remove(i)
        return
      }
    }
  }

  function closeLive() {
    liveModel.clear()
    root.liveCount = 0
  }

  function clearUnread() {
    root.unreadCount = 0
  }

  function curlJson(kind, body) {
    if (apiProc.running) return false
    root.apiKind = kind
    apiBodyFile.setText(body)
    var cmd = ["curl", "-sS", "-w", "\n%{http_code}"].concat(
      Model.curlBounds(Model.API_MAX_BYTES),
      ["-X", "POST", "-H", "Content-Type: application/json",
       "--data-binary", "@" + apiBodyPath,
       Model.jsonUrl(root.url)]
    )
    apiProc.command = cmd
    apiProc.running = true
    return true
  }

  function startLoginStep1() {
    if (apiProc.running) return false
    return curlJson("login1", Model.loginStep1Body())
  }

  function startLoginStep2(session) {
    if (apiProc.running) return false
    // Compute MD5 hash via shell
    root.apiKind = "md5"
    var challenge = root.username + ":" + session + ":" + root.password
    md5Proc.command = ["bash", "-c", "printf '%s' \"$1\" | md5sum | cut -d' ' -f1", "--", challenge]
    md5Proc.running = true
    return true
  }

  function startCamlist() {
    if (!root.session) return false
    return curlJson("camlist", Model.camlistBody(root.session))
  }

  function startStills() {
    if (stillsProc.running || !root.connected) return false
    var cmd = ["curl", "-sS"].concat(Model.curlBounds(Model.IMAGE_MAX_BYTES))
    var added = 0
    for (var i = 0; i < root.cameras.length; i++) {
      var imgUrl = Model.imageUrl(root.url, root.cameras[i].name)
      if (root.session) imgUrl += "&session=" + root.session
      cmd.push("-o", stillPath(root.cameras[i].name), imgUrl)
      added += 1
    }
    if (!added) return false
    stillsProc.command = cmd
    stillsProc.running = true
    return true
  }

  function splitHttp(text) {
    var raw = String(text || "")
    var nl = raw.lastIndexOf("\n")
    if (nl === -1) return { body: raw, status: 0 }
    return { body: raw.slice(0, nl), status: parseInt(raw.slice(nl + 1), 10) || 0 }
  }

  function handleApiSuccess(text) {
    var parsed = splitHttp(text)

    if (root.apiKind === "login1") {
      var session = Model.parseLoginStep1(parsed.body)
      if (!session) {
        root.needsLogin = true
        root.statusText = "Login failed (no session)"
        return
      }
      root.session = session
      startLoginStep2(session)
      return
    }

    if (root.apiKind === "login2") {
      var ok = Model.parseLoginStep2(parsed.body)
      if (!ok) {
        root.needsLogin = true
        root.signedIn = false
        root.statusText = "Login failed (bad credentials)"
        return
      }
      root.connected = true
      root.signedIn = true
      root.needsLogin = false
      root.statusText = "Authenticated"
      startCamlist()
      return
    }

    if (root.apiKind === "camlist") {
      var cams = Model.parseCamlist(parsed.body)
      root.cameras = cams
      root.statusText = cams.length + " cameras"
      if (root.panelOpen) Qt.callLater(root.startStills)
      return
    }
  }

  function handleApiFailure() {
    if (root.apiKind === "login1" || root.apiKind === "login2") {
      root.needsLogin = true
      root.signedIn = false
      root.statusText = "Login failed"
      return
    }
    root.connected = false
    root.signedIn = false
    root.statusText = "Unreachable"
    if (root.username && !root.password) root.needsLogin = true
  }

  function tick() {
    if (apiProc.running || md5Proc.running) return
    if (!root.connected && root.username && root.password) {
      startLoginStep1()
      return
    }
    if (!root.connected) {
      root.needsLogin = true
      root.statusText = root.username ? "Needs password" : "Not configured"
      return
    }
    startCamlist()
  }

  FileView {
    id: passwordFile
    path: root.passwordPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = Model.parsePasswordFile(text())
      root.password = parsed.password
    }
    onLoadFailed: root.password = ""
    onFileChanged: reload()
  }

  FileView {
    id: apiBodyFile
    path: root.apiBodyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  ListModel {
    id: liveModel
  }

  Instantiator {
    model: liveModel
    delegate: Process {
      required property string name
      required property string mediaUrl
      required property string title
      required property string geometry
      running: mediaUrl !== ""
      command: [
        "mpv",
        "--profile=low-latency",
        "--untimed=yes",
        "--cache=no",
        "--no-audio",
        "--really-quiet",
        "--title=" + title,
        "--wayland-app-id=omaBlueIris-live",
        "--force-window=immediate",
        "--geometry=" + geometry,
        "--video-aspect-override=" + (root.aspectRatio === "4:3" ? "4/3" : "16/9"),
        mediaUrl
      ]
      onExited: if (!running) root.dropLive(name)
    }
  }

  Process {
    id: ensureCacheProc
    running: false
  }

  Process {
    id: chmodProc
    running: false
  }

  Process {
    id: openProc
    running: false
  }

  Process {
    id: stillsProc
    running: false
    onExited: root.stillRevision += 1
  }

  Process {
    id: md5Proc
    running: false
    stdout: StdioCollector {
      id: md5Out
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.handleApiFailure()
        return
      }
      var hash = String(md5Out.text || "").replace(/\s+/g, "")
      var body = JSON.stringify({
        cmd: "login",
        session: root.session,
        response: hash
      })
      root.curlJson("login2", body)
    }
  }

  Process {
    id: apiProc
    running: false
    stdout: StdioCollector {
      id: apiOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.handleApiFailure()
      else root.handleApiSuccess(apiOut.text)
      Qt.callLater(root.tick)
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  Timer {
    interval: Math.max(1, root.refreshSeconds) * 1000
    running: root.panelOpen && root.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: root.startStills()
  }

  // Refresh camlist every 60s while connected
  Timer {
    interval: 60000
    running: root.connected
    repeat: true
    onTriggered: if (!apiProc.running) root.startCamlist()
  }

  onPanelOpenChanged: if (!root.panelOpen && stillsProc.running) stillsProc.running = false

  onUrlChanged: {
    root.session = ""
    root.connected = false
    root.signedIn = false
    root.statusText = "Connecting…"
    root.closeLive()
  }

  Component.onCompleted: {
    passwordFile.reload()
    ensureCacheProc.command = ["mkdir", "-p", cacheDir]
    ensureCacheProc.running = true
  }
}
