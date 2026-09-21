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

-- Pin workspaces to monitors.
-- Ultrawide gets 1-8, Dell gets 9.
hl.workspace_rule({ workspace = "1", monitor = ultrawide })
hl.workspace_rule({ workspace = "2", monitor = ultrawide })
hl.workspace_rule({ workspace = "3", monitor = ultrawide })
hl.workspace_rule({ workspace = "4", monitor = ultrawide })
hl.workspace_rule({ workspace = "5", monitor = ultrawide })
hl.workspace_rule({ workspace = "6", monitor = ultrawide })
hl.workspace_rule({ workspace = "7", monitor = ultrawide })
hl.workspace_rule({ workspace = "8", monitor = ultrawide })
hl.workspace_rule({ workspace = "9", monitor = dell, default = true })
