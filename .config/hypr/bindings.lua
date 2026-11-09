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

-- Super + 9 is the Dell U2719DX (the top screen), from any screen.
-- Omarchy 4.5.0 gave every monitor its own workspaces 1-10 (default/hypr/monitor-workspaces.lua),
-- so the old "workspace 9 lives on the Dell" rule no longer holds. These keys go to the Dell
-- itself, found by its make/model/serial so a connector rename (DP-5 today) doesn't break them:
--   SUPER + 9                 focus the Dell
--   SUPER + SHIFT + 9         send the active window to the workspace the Dell shows, and follow it
--   SUPER + SHIFT + ALT + 9   the same without following
local DELL = "Dell Inc. DELL U2719DX JTFZ023"

local function dell_monitor()
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.description == DELL then
      return monitor
    end
  end
end

function o.dell_focus()
  local fn = function()
    local dell = dell_monitor()
    if dell then
      hl.dispatch(hl.dsp.focus({ monitor = dell.name }))
    end
  end
  o.bind_expressions[fn] = "o.dell_focus()"
  return fn
end

function o.dell_move_window(follow)
  local fn = function()
    local dell, window = dell_monitor(), hl.get_active_window()
    if not dell or not window or not dell.active_workspace then
      return
    end
    hl.dispatch(hl.dsp.window.move({
      workspace = tostring(dell.active_workspace.id),
      follow = follow ~= false,
      window = "address:" .. window.address,
    }))
  end
  o.bind_expressions[fn] = "o.dell_move_window(" .. (follow == false and "false" or "") .. ")"
  return fn
end

o.rebind("SUPER + 9", "Go to the Dell monitor", o.dell_focus())
o.rebind("SUPER + SHIFT + 9", "Move window to the Dell monitor", o.dell_move_window())
o.rebind("SUPER + SHIFT + ALT + 9", "Move window silently to the Dell monitor", o.dell_move_window(false))

-- Dictation keys from before Alt + Space and Right Alt became the defaults.
-- Remove these lines to give the keys back to applications.
if o.dictation_installed and o.dictation_installed() then
  o.bind("SUPER + CTRL + X", "Toggle dictation", "omarchy-dictation toggle")
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
end
