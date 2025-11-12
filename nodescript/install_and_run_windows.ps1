Param(
  [int]$Port = 8080,
  [string]$TaskName = 'PeopleChainDiscoveryNode',
  [string]$NodeExe = 'node'
)

$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$serverJs = Join-Path $here 'discovery_server.js'
if (!(Test-Path $serverJs)) { throw "discovery_server.js not found at $serverJs" }

function Resolve-NodeExe {
  param([string]$exe)
  try { return (Get-Command $exe -ErrorAction Stop).Path } catch {
    $default = 'C:\\Program Files\\nodejs\\node.exe'
    if (Test-Path $default) { return $default }
    throw "node executable not found. Install Node.js or pass -NodeExe path"
  }
}

$nodePath = Resolve-NodeExe -exe $NodeExe

Write-Host "Registering scheduled task '$TaskName' to auto-start at logon and startup..."

# Build action and triggers
$arg = '"' + $serverJs + '" --port ' + $Port
$action = New-ScheduledTaskAction -Execute $nodePath -Argument $arg
$triggers = @(
  (New-ScheduledTaskTrigger -AtLogOn),
  (New-ScheduledTaskTrigger -AtStartup)
)

# Use current user context
$userId = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
# Use a valid LogonType; InteractiveToken is not a valid enum name. "Interactive" maps to
# "Run only when user is logged on" which is appropriate for opening the monitor on login.
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel LeastPrivilege

# Create or update
try {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
} catch {}

$task = New-ScheduledTask -Action $action -Trigger $triggers -Principal $principal -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable)
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null

Write-Host "Starting task '$TaskName'..."
Start-ScheduledTask -TaskName $TaskName

Start-Sleep -Seconds 1

try { Start-Process "http://localhost:$Port/" } catch {}

Write-Host "Done. Monitor: http://localhost:$Port/"