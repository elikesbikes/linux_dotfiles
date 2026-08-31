var PLUGIN_ID = "ecloaiza.blueiris"
var DEFAULT_URL = "http://127.0.0.1:81"
var API_MAX_BYTES = 2 * 1024 * 1024
var IMAGE_MAX_BYTES = 8 * 1024 * 1024

function curlBounds(maxBytes) {
  var n = parseInt(maxBytes, 10)
  if (!(n > 0)) n = API_MAX_BYTES
  return ["--max-time", "8", "--max-filesize", String(n)]
}

function normalizeUrl(url) {
  var value = String(url || "").replace(/^\s+|\s+$/g, "").replace(/\/+$/, "")
  return value || DEFAULT_URL
}

function pluginSettings(config, id) {
  var key = String(id || PLUGIN_ID)
  var empty = { url: DEFAULT_URL, username: "", refreshSeconds: 5, aspectRatio: "16:9" }
  if (!config || typeof config !== "object") return empty

  function fromEntry(entry) {
    if (!entry || typeof entry !== "object") return null
    if (String(entry.id || "") !== key) return null
    return {
      url: normalizeUrl(entry.url),
      username: String(entry.username || ""),
      refreshSeconds: Math.max(1, parseInt(entry.refreshSeconds, 10) || 5),
      aspectRatio: String(entry.aspectRatio || "16:9") === "4:3" ? "4:3" : "16:9"
    }
  }

  var bar = config.bar && config.bar.layout ? config.bar.layout : {}
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = bar[sections[s]] || []
    for (var i = 0; i < entries.length; i++) {
      var found = fromEntry(entries[i])
      if (found) return found
    }
  }

  var plugins = config.plugins || []
  for (var p = 0; p < plugins.length; p++) {
    var plugin = fromEntry(plugins[p])
    if (plugin) return plugin
  }
  return empty
}

function parsePasswordFile(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return { password: data && typeof data.password === "string" ? data.password : "" }
  } catch (e) {
    return { password: "" }
  }
}

function serializePasswordFile(password) {
  return JSON.stringify({ password: String(password || "") }) + "\n"
}

// Blue Iris JSON API uses MD5 challenge-response auth.
// Step 1: POST {"cmd":"login"} → get session id
// Step 2: POST {"cmd":"login","session":id,"response":MD5(user:session:pass)} → authenticated
function loginStep1Body() {
  return JSON.stringify({ cmd: "login" })
}

function loginStep2Body(session, username, password) {
  return JSON.stringify({
    cmd: "login",
    session: String(session),
    response: "__MD5__" + String(username || "") + ":" + String(session) + ":" + String(password || "")
  })
}

function camlistBody(session) {
  return JSON.stringify({ cmd: "camlist", session: String(session) })
}

function jsonUrl(base) {
  return normalizeUrl(base) + "/json"
}

function imageUrl(base, camera) {
  return normalizeUrl(base) + "/image/" + encodeURIComponent(String(camera || "")) + "?q=60&s=80"
}

function mjpegUrl(base, camera) {
  return normalizeUrl(base) + "/mjpg/" + encodeURIComponent(String(camera || "")) + "/video.mjpg"
}

function parseLoginStep1(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return String(data.session || "")
  } catch (e) {
    return ""
  }
}

function parseLoginStep2(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (data.result === "success") return true
    return false
  } catch (e) {
    return false
  }
}

function parseCamlist(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!Array.isArray(data.data)) return []
    var cameras = []
    for (var i = 0; i < data.data.length; i++) {
      var cam = data.data[i]
      if (!cam || !cam.optionValue) continue
      // Skip groups (type "group") and the "index" pseudo-camera
      if (cam.group || cam.optionValue === "index") continue
      cameras.push({
        name: String(cam.optionValue),
        displayName: String(cam.optionDisplay || cam.optionValue),
        isOnline: cam.isOnline !== false,
        isEnabled: cam.isEnabled !== false
      })
    }
    cameras.sort(function(a, b) {
      return a.displayName < b.displayName ? -1 : a.displayName > b.displayName ? 1 : 0
    })
    return cameras
  } catch (e) {
    return []
  }
}

function liveGeometry(index, aspect) {
  var i = Math.max(0, parseInt(index, 10) || 0)
  var w = 640
  var h = aspect === "4:3" ? 480 : 360
  var gap = 16
  var margin = 40
  var col = Math.floor(i / 2)
  var row = i % 2
  return w + "x" + h + "-" + (margin + col * (w + gap)) + "-" + (margin + row * (h + gap))
}
