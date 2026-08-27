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

-- Top: Dell U2719DX
hl.monitor({ output = "DP-5", mode = "preferred", position = "352x0", scale = omarchy_monitor_scale })

-- Bottom: Gigabyte G34WQC ultrawide
hl.monitor({ output = "DP-3", mode = "preferred", position = "0x1152", scale = omarchy_monitor_scale })

-- Pin workspaces 3-5 to the Gigabyte ultrawide (DP-3). Without this, new
-- workspaces default to whichever monitor is focused the first time you
-- switch to them, which was landing them on the Dell (DP-5).
hl.workspace_rule({ workspace = "3", monitor = "DP-3" })
hl.workspace_rule({ workspace = "4", monitor = "DP-3" })
hl.workspace_rule({ workspace = "5", monitor = "DP-3" })
