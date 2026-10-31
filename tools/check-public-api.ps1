param([switch]$Update)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$interface = Join-Path $projectRoot "pkg.generated.mbti"
$baseline = Join-Path $projectRoot "api/public-api.sha256"

Push-Location $projectRoot
try {
  moon info
  if ($LASTEXITCODE -ne 0) { throw "moon info failed with exit code $LASTEXITCODE." }
  if (-not (Test-Path -LiteralPath $interface -PathType Leaf)) {
    throw "moon info did not generate pkg.generated.mbti."
  }
  $normalized = [IO.File]::ReadAllText($interface).Replace("`r`n", "`n").Replace("`r", "`n")
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))
  } finally {
    $sha.Dispose()
  }
  $actual = ([BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant()
  if ($Update) {
    [IO.File]::WriteAllText($baseline, "$actual`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Updated the public API baseline to $actual. Review pkg.generated.mbti before committing."
    return
  }
  if (-not (Test-Path -LiteralPath $baseline -PathType Leaf)) {
    throw "Missing API baseline $baseline. Run with -Update after reviewing the generated interface."
  }
  $expected = (Get-Content -LiteralPath $baseline -Raw).Trim()
  if ($actual -cne $expected) {
    throw "Public API changed unexpectedly.`nExpected: $expected`nActual:   $actual`nReview pkg.generated.mbti, update docs and CHANGELOG, then run tools/check-public-api.ps1 -Update."
  }
  Write-Host "Public API snapshot passed: $actual"
} finally {
  Pop-Location
}
