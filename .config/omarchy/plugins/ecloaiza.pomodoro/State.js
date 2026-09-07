.pragma library

var focusPresets = [5, 10, 15, 20, 25, 30, 45, 50, 60, 90]
var focusIndex = 4
var lapLength = 25
var shortBreak = 5
var longBreak = 15
var lapsUntilLong = 4
var phase = "idle"
var completedLaps = 0
var running = false
var remaining = 25 * 60
var deadline = 0
var initialized = false

function init(settings) {
    if (initialized) return
    initialized = true
    lapLength = settings.lapLength || 25
    shortBreak = settings.shortBreak || 5
    longBreak = settings.longBreak || 15
    lapsUntilLong = Math.max(1, settings.lapsUntilLong || 4)
    focusIndex = Math.max(0, focusPresets.indexOf(lapLength))
    remaining = lapLength * 60
}

function minutesFor(which) {
    if (which === "short") return shortBreak
    if (which === "long") return longBreak
    return lapLength
}
