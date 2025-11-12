Param(
  [int]$Port = 8080,
  [string]$TaskName = 'PeopleChainDiscoveryNode'
)

Write-Host "Stopping discovery server..."

try {
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($task) {
    try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null } catch {}
    Write-Host "Stopped scheduled task '$TaskName'."
  }
} catch {}

try {
  $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($conn -and $conn.OwningProcess) {
    Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
    Write-Host "Killed process on port $Port (PID $($conn.OwningProcess))."
  }
} catch {}

try {
  $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -match 'discovery_server.js' }
  if ($procs) {
    $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Write-Host "Terminated node.exe instances for discovery_server.js."
  }
} catch {}

Write-Host "Done."