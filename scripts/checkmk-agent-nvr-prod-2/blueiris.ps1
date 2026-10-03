# CheckMK local check (Windows, nvr-prod-2): Blue Iris is up and how much of the machine it uses. Lets us see if the AI work (Ollama) ever squeezes the recorder.
$svc = Get-Service -Name BlueIris -ErrorAction SilentlyContinue
$p = Get-Process -Name BlueIris -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $svc) { Write-Output '2 "Blue Iris" - service BlueIris not found'; exit 0 }
if ($svc.Status -ne 'Running' -or -not $p) { Write-Output ('2 "Blue Iris" - service is {0}' -f $svc.Status); exit 0 }
$cpu = (Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "IDProcess=$($p.Id)").PercentProcessorTime
$tot = (Get-CimInstance Win32_Processor).LoadPercentage
$mem = [int]($p.WorkingSet64/1MB)
$st = 0; if ($tot -ge 85) { $st = 1 }; if ($tot -ge 95) { $st = 2 }
"{0} `"Blue Iris`" bi_cpu_pct={1}|bi_mem_mb={2}|host_cpu_pct={3};85;95 service running, Blue Iris {1}% of one core, {2} MB, whole machine CPU {3}%" -f $st,$cpu,$mem,$tot
