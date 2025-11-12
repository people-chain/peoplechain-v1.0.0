Param(
  [int]$Port = 8080,
  [string]$NodeExe = 'node'
)

$ErrorActionPreference = 'Stop'

$serverJs = Join-Path $PSScriptRoot 'discovery_server.js'
if (!(Test-Path $serverJs)) {
  Write-Error "discovery_server.js not found at $serverJs"
}

function Resolve-NodeExe {
  param([string]$exe)
  try {
    $cmd = Get-Command $exe -ErrorAction Stop
    return $cmd.Path
  } catch {
    $default = 'C:\\Program Files\\nodejs\\node.exe'
    if (Test-Path $default) { return $default }
    throw "node executable not found. Install Node.js or pass -NodeExe path"
  }
}

$resolvedNode = Resolve-NodeExe -exe $NodeExe
Write-Host "Running discovery server on port $Port... (Ctrl+C to stop)"
& $resolvedNode $serverJs --port $Port