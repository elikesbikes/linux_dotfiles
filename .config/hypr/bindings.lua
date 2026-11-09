-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")
o.bind("SUPER + ALT + + CTRL + P", "Screenshot", "omarchy-capture-screenshot")
o.bind("SUPER + ALT + + CTRL + T", "Extract text (OCR) from screenshot", "omarchy-capture-text")
-- Unbind existing SUPER+SHIFT+A (was: ChatGPT webapp)
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "ChatTARS", { webapp = "https://chattars.home.elikesbikes.com/", focus = true })
-- ChatTARS webapp always opens on workspace 2 (Brave webapp class)
o.window("^brave-chattars\\.home\\.elikesbikes\\.com__.*", { workspace = "2" })
-- Unbind existing SUPER+RETURN (was: Terminal / kitty)
hl.unbind("SUPER + RETURN")
-- herdr desktop app as the main terminal; focuses the open window instead of starting a second copy
o.bind("SUPER + RETURN", "Herdr app", { launch = "/home/ecloaiza/.local/bin/herdr-app", focus = "^herdr-app$" })

-- Old global workspace numbering (owner choice 2026-11-09): Super + 1-0 always mean workspaces
-- 1-10, wherever the focus is. The ultrawide has 1-8 and the Dell has 9 (rules in monitors.lua).
-- Omarchy 4.5.0 binds these keys to its per-monitor blocks (o.workspaces.focus / move_window), so
-- they are rebound to plain Hyprland here. Omarchy binds them by keycode (code:10 = 1 ... code:19 = 0).
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  local ws = tostring(workspace)
  o.rebind("SUPER + " .. key, "Switch to workspace " .. ws, hl.dsp.focus({ workspace = ws }))
  o.rebind("SUPER + SHIFT + " .. key, "Move window to workspace " .. ws, hl.dsp.window.move({ workspace = ws, follow = true }))
  o.rebind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. ws, hl.dsp.window.move({ workspace = ws, follow = false }))
end

-- Move the active workspace to the monitor in a direction, keeping its number (Omarchy's version
-- renumbers it into that monitor's block).
function o.workspace_to_monitor(direction)
  local fn = function()
    local target = hl.get_monitor(direction)
    if target then
      hl.dispatch(hl.dsp.workspace.move({ monitor = target.name }))
    end
  end
  o.bind_expressions[fn] = "o.workspace_to_monitor(" .. string.format("%q", direction) .. ")"
  return fn
end

for key, direction in pairs({ LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d" }) do
  o.rebind("SUPER + SHIFT + ALT + " .. key, "Move workspace to " .. key:lower() .. " monitor", o.workspace_to_monitor(direction))
end

-- Dictation keys from before Alt + Space and Right Alt became the defaults.
-- Remove these lines to give the keys back to applications.
if o.dictation_installed and o.dictation_installed() then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
end
