# CheckMK local checks (Windows, nvr-prod-2): NVIDIA GPU, seven services from ONE nvidia-smi call.
# Only readings this card actually exposes (verified 2026-10-03): no memory temperature, no ECC, no retired pages on a Quadro P4000.
$smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
if (-not $smi) { $smi = "C:\Windows\System32\nvidia-smi.exe" }
$q = "name,fan.speed,temperature.gpu,utilization.gpu,utilization.memory,utilization.encoder,utilization.decoder,power.draw,power.limit,clocks.sm,clocks.max.sm,clocks.mem,clocks.max.mem,clocks.gr,pstate,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,memory.used,memory.total,encoder.stats.sessionCount,encoder.stats.averageFps,encoder.stats.averageLatency,clocks_throttle_reasons.active,driver_version"
$line = & $smi --query-gpu=$q --format=csv,noheader,nounits 2>$null
if (-not $line) { Write-Output '2 "GPU NVIDIA driver" - nvidia-smi returned nothing (driver or passthrough problem?)'; exit 0 }
$f = ($line -split ',') | ForEach-Object { $_.Trim() }
function N($v) { if ($v -match '^[\d.]+$') { [double]$v } else { 0 } }
$name=$f[0]; $fan=N $f[1]; $temp=N $f[2]; $ug=N $f[3]; $um=N $f[4]; $ue=N $f[5]; $ud=N $f[6]; $pd=N $f[7]; $pl=N $f[8]
$csm=N $f[9]; $cmx=N $f[10]; $cmem=N $f[11]; $cmemx=N $f[12]; $cgr=N $f[13]; $ps=$f[14]
$pg=N $f[15]; $pgm=N $f[16]; $pw=N $f[17]; $pwm=N $f[18]; $mu=N $f[19]; $mt=N $f[20]; $es=N $f[21]; $ef=N $f[22]; $el=N $f[23]
$mask=[Convert]::ToInt64($f[24],16); $drv=$f[25]
$pct=[int](100*$mu/[math]::Max($mt,1)); $ppct=[int](100*$pd/[math]::Max($pl,1))
$busy = $ug -ge 30
# 1. temperature and fan
$st=0; $w=""; if ($temp -ge 85) {$st=1;$w=" - hot"}; if ($temp -ge 92) {$st=2;$w=" - CRITICAL temperature"}
"{0} `"GPU temperature`" gpu_temp_c={1};85;92|gpu_fan_pct={2} {3}: {1} C, fan {2}%{4}" -f $st,$temp,$fan,$name,$w
# 2. utilization (informational: a busy GPU is normal while Ollama works)
"0 `"GPU utilization`" gpu_util_pct={0}|gpu_mem_ctrl_pct={1}|gpu_encoder_pct={2}|gpu_decoder_pct={3} GPU {0}%, memory controller {1}%, video encoder {2}%, video decoder {3}%, performance state {4}" -f $ug,$um,$ue,$ud,$ps
# 3. video memory
$st=0; if ($pct -ge 90) {$st=1}; if ($pct -ge 97) {$st=2}
"{0} `"GPU video memory`" vram_used_mb={1};;;0;{2}|vram_used_pct={3};90;97 {1}/{2} MiB used ({3}%)" -f $st,[int]$mu,[int]$mt,$pct
# 4. power
$st=0; if ($ppct -ge 98) {$st=1}
"{0} `"GPU power`" power_w={1}|power_limit_w={2}|power_pct={3};98 {1} W of {2} W limit ({3}%)" -f $st,$pd,$pl,$ppct
# 5. clocks and throttling (flags: 0x1 idle, 0x4 sw power cap, 0x20 sw thermal, 0x8 hw slowdown, 0x40 hw thermal, 0x80 hw power brake)
$why=@(); $st=0
if ($mask -band 0x4)  { $why+="software power cap" }
if ($mask -band 0x20) { $why+="software thermal slowdown"; $st=1 }
if ($mask -band (0x8 -bor 0x40 -bor 0x80)) { $why+="HARDWARE slowdown (thermal/power brake)"; $st=2 }
if (($mask -band 0x4) -and $busy -and $st -lt 1) { $st=1 }
$idle = if ($mask -band 0x1) { "idle" } else { "active" }
$wtxt = if ($why.Count) { " - throttling: " + ($why -join ", ") } else { "" }
"{0} `"GPU clocks`" clock_sm_mhz={1};;;0;{2}|clock_mem_mhz={3};;;0;{4}|clock_graphics_mhz={5} SM {1}/{2} MHz, memory {3}/{4} MHz, state {6} ({7}){8}" -f $st,[int]$csm,[int]$cmx,[int]$cmem,[int]$cmemx,[int]$cgr,$ps,$idle,$wtxt
# 6. PCIe link (passthrough health): width below maximum means a degraded link; generation drops at idle by design
$st=0; $n=""
if ($pw -lt $pwm) { $st=2; $n=" - LINK WIDTH DEGRADED" } elseif ($busy -and $pg -lt $pgm) { $st=1; $n=" - generation below maximum while busy" }
"{0} `"GPU PCIe link`" pcie_gen={1};;;0;{2}|pcie_width={3};;;0;{4} generation {1}/{2}, width x{3}/x{4}{5}" -f $st,[int]$pg,[int]$pgm,[int]$pw,[int]$pwm,$n
# 7. video encoder sessions (Blue Iris hardware encode, if used)
"0 `"GPU encoder sessions`" encoder_sessions={0}|encoder_fps={1}|encoder_latency_us={2} {0} session(s), {1} fps average, {2} us latency (driver {3})" -f [int]$es,[int]$ef,[int]$el,$drv
