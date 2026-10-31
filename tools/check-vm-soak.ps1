param([switch]$Quick)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
  moon build --target native --release cmd/vm_soak
  if ($LASTEXITCODE -ne 0) { throw "VM soak build failed." }
  $executable = @(
    (Join-Path $projectRoot "_build/native/release/build/cmd/vm_soak/vm_soak.exe"),
    (Join-Path $projectRoot "_build/native/release/build/cmd/vm_soak/vm_soak")
  ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
  if (-not $executable) { throw "VM soak executable was not produced." }
  [string[]]$soakArguments = @()
  if ($Quick) { $soakArguments += "--quick" }
  $output = (& $executable @soakArguments 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw "VM soak failed:`n$output" }
  if ($output -notmatch '^soak_passed iterations=(?<count>\d+) callbacks=\k<count> finalized=\k<count>') {
    throw "VM soak did not report a valid invariant summary:`n$output"
  }
  Write-Host $output
} finally {
  Pop-Location
}
