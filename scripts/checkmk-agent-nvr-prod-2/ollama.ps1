# CheckMK local checks (Windows, nvr-prod-2): Ollama service, API, models, errors and storage.
$d = "C:\Ollama"
# 1. scheduled task + process
$task = Get-ScheduledTask -TaskName "Ollama" -ErrorAction SilentlyContinue
$procs = @(Get-Process -Name ollama -ErrorAction SilentlyContinue)
if (-not $task) { Write-Output '2 "Ollama service" - scheduled task "Ollama" is missing'; }
elseif ($procs.Count -eq 0) { Write-Output ('2 "Ollama service" - process not running (task state: {0})' -f $task.State) }
else {
  $prio = ($procs | Select-Object -First 1).PriorityClass
  $st = 0; $note = ""
  if ($prio -ne 'BelowNormal') { $st = 1; $note = " - priority is $prio, expected BelowNormal (Blue Iris must win CPU contention)" }
  $mem = [int](($procs | Measure-Object WorkingSet64 -Sum).Sum/1MB)
  "{0} `"Ollama service`" ollama_mem_mb={1} task {2}, {3} process(es), priority {4}, {1} MB{5}" -f $st,$mem,$task.State,$procs.Count,$prio,$note
}
# 2. API, models, loaded models
try {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $ver = (Invoke-RestMethod -Uri http://127.0.0.1:11434/api/version -TimeoutSec 5).version
  $ms = [int]$sw.Elapsed.TotalMilliseconds
  $tags = (Invoke-RestMethod -Uri http://127.0.0.1:11434/api/tags -TimeoutSec 5).models.name
  $ps = (Invoke-RestMethod -Uri http://127.0.0.1:11434/api/ps -TimeoutSec 5).models
  $miss = @("qwen3:4b","nomic-embed-text") | Where-Object { -not ($tags -match [regex]::Escape($_)) }
  $loaded = @($ps).Count; $vram = [int]((($ps | Measure-Object size_vram -Sum).Sum)/1MB)
  $st = 0; $note = ", models present"
  if ($miss) { $st = 1; $note = ", MISSING model(s): " + ($miss -join " ") }
  if ($ms -gt 1000) { if ($st -lt 1) { $st = 1 }; $note += ", slow answer" }
  "{0} `"Ollama API`" response_ms={1};1000;5000|models_loaded={2}|model_vram_mb={3} version {4}, {1} ms, {2} loaded in memory ({3} MB video){5}" -f $st,$ms,$loaded,$vram,$ver,$note
} catch { Write-Output ('2 "Ollama API" - not answering on 127.0.0.1:11434 ({0})' -f $_.Exception.Message.Split("`n")[0]) }
# 3. recent errors in the log (last 400 lines, ERROR level, last 15 minutes)
$log = "$d\logs\ollama.log"
if (Test-Path $log) {
  $cut = (Get-Date).AddMinutes(-15)
  $errs = @(Get-Content $log -Tail 400 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'level=ERROR' -and $_ -match 'time=(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)' -and ([datetime]$Matches[1]) -gt $cut })
  $st = 0; if ($errs.Count -ge 1) { $st = 1 }; if ($errs.Count -ge 10) { $st = 2 }
  $last = if ($errs.Count) { " - last: " + ($errs[-1] -replace '^time=\S+ level=ERROR source=\S+ msg=','').Substring(0,[Math]::Min(120,($errs[-1] -replace '^time=\S+ level=ERROR source=\S+ msg=','').Length)) } else { "" }
  "{0} `"Ollama log errors`" errors_15min={1};1;10 {1} error line(s) in the last 15 minutes{2}" -f $st,$errs.Count,$last
}
# 4. storage: model folder size and free space on C:
$size = (Get-ChildItem "$d\models" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
$free = [math]::Round((Get-PSDrive C).Free/1GB,1)
$st = 0; if ($free -lt 15) { $st = 1 }; if ($free -lt 8) { $st = 2 }
"{0} `"Ollama model storage`" models_gb={1}|c_free_gb={2};15;8 models {1} GB in C:\Ollama\models, C: has {2} GB free" -f $st,[math]::Round($size/1GB,2),$free
