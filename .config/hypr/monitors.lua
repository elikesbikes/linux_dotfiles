-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1.25

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Stacked layout: Dell U2719DX on top, Gigabyte G34WQC ultrawide on the bottom.
-- Positions are in logical (post-scale) pixels at scale 1.25:
--   DP-5 Dell      2560x1440 -> 2048x1152
--   DP-3 Gigabyte  3440x1440 -> 2752x1152
-- The Dell is centered horizontally over the wider ultrawide: (2752 - 2048) / 2 = 352.

local dell = "desc:Dell Inc. DELL U2719DX JTFZ023"
local ultrawide = "desc:GIGA-BYTE TECHNOLOGY CO. LTD. G34WQC A 23082B002289"

-- Top: Dell U2719DX — default workspace 9
hl.monitor({ output = dell, mode = "preferred", position = "352x0", scale = omarchy_monitor_scale })

-- Bottom: Gigabyte G34WQC ultrawide
hl.monitor({ output = ultrawide, mode = "preferred", position = "0x1152", scale = omarchy_monitor_scale })

-- One global workspace numbering: ultrawide 1-8, Dell 9. Numbers never change.
--
-- Omarchy 4.5.0 (2026-11-08) gives every monitor its own block of workspaces (ultrawide 1-10, Dell
-- 11-20, see /usr/share/omarchy/default/hypr/monitor-workspaces.lua) and renumbers workspaces while a
-- monitor is off. The owner wants the old behavior (2026-11-09), which takes three overrides:
--   1. here: Omarchy's re-sorting is switched off. Its handlers (Hyprland start, config reload,
--      monitor added/removed) call o.workspaces.reconcile at event time, so a no-op stops them all.
--   2. bindings.lua: Super + 1-0 and the "move workspace to monitor" keys go back to plain Hyprland.
--   3. the bar uses the clone ecloaiza.workspaces (global numbers) instead of omarchy.workspaces.
-- After every Omarchy update, check that monitor-workspaces.lua still exposes o.workspaces.reconcile.
o.workspaces.reconcile = function() end

hl.workspace_rule({ workspace = "1", monitor = ultrawide })
hl.workspace_rule({ workspace = "2", monitor = ultrawide })
hl.workspace_rule({ workspace = "3", monitor = ultrawide })
hl.workspace_rule({ workspace = "4", monitor = ultrawide })
hl.workspace_rule({ workspace = "5", monitor = ultrawide })
hl.workspace_rule({ workspace = "6", monitor = ultrawide })
hl.workspace_rule({ workspace = "7", monitor = ultrawide })
hl.workspace_rule({ workspace = "8", monitor = ultrawide })
hl.workspace_rule({ workspace = "9", monitor = dell, default = true })

-- Workspace 9 goes back to the Dell every time a monitor (re)connects (2026-11-20, linux_dotfiles#25).
--
-- With Omarchy's re-sorting off (above), nothing returns 9 after the Dell drops off: Hyprland parks 9
-- on the ultrawide, and when the Dell comes back it opens an empty workspace 11 instead. This happens
-- when both screens power-cycle (three times in one morning on 2026-11-20).
--
-- The check runs half a second after the event (timer timeout is in milliseconds), because both
-- screens come back one after the other and Hyprland is still placing workspaces in between. It is
-- safe to run any number of times: it does nothing when 9 is already showing on the Dell.
-- It does not undo a move made by hand (Super + Shift + Alt + arrows) until the next reconnect.
local dell_description = dell:gsub("^desc:", "")

local function dell_monitor()
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.description == dell_description then
      return monitor
    end
  end

  return nil
end

local function return_nine_to_dell()
  local monitor = dell_monitor()
  local nine = hl.get_workspace(9)

  -- No Dell, or no workspace 9 (it has no windows): nothing to bring back.
  if not monitor or not nine or not nine.monitor then
    return
  end

  local focused = hl.get_active_window()
  local changed = false

  if nine.monitor.name ~= monitor.name then
    hl.dispatch(hl.dsp.workspace.move({ workspace = "9", monitor = monitor.name }))
    changed = true
  end

  -- Read both again: the move changes what each of them reports.
  monitor = dell_monitor()
  nine = hl.get_workspace(9)

  if monitor and nine and nine.monitor and nine.monitor.name == monitor.name
    and (not monitor.active_workspace or monitor.active_workspace.id ~= 9) then
    monitor:set_workspace({ workspace = nine.name })
    changed = true
  end

  -- Moving a workspace can take the focus with it; give it back to the window that had it.
  if changed and focused and hl.get_window("address:" .. focused.address) then
    hl.dispatch(hl.dsp.focus({ window = "address:" .. focused.address }))
  end
end

hl.on("monitor.added", function()
  hl.timer(return_nine_to_dell, { type = "oneshot", timeout = 500 })
end)
