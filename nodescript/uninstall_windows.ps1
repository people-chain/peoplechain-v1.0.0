[CmdletBinding()]
param(
  [int]$Port = 8080,
  [string]$TaskName = 'PeopleChainDiscoveryNode'
)

Write-Host "Uninstalling discovery server..." -ForegroundColor Cyan

# Stop anything running
& (Join-Path $PSScriptRoot 'stop_windows.ps1') -Port $Port -TaskName $TaskName

# Disable and remove scheduled task
try {
  $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($task) {
    Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Removed scheduled task '$TaskName'." -ForegroundColor Green
  } else {
    Write-Host "Scheduled task '$TaskName' not found." -ForegroundColor Yellow
  }
} catch {}

Write-Host "Uninstall complete." -ForegroundColor Yellow
