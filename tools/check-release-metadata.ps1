$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Read-Text([string]$RelativePath) {
  [System.IO.File]::ReadAllText((Join-Path $root $RelativePath))
}

function Require-Match([string]$Text, [string]$Pattern, [string]$Description) {
  $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
  if (-not $match.Success) {
    throw "Could not read $Description."
  }
  $match.Groups["value"].Value
}

$moduleText = Read-Text "moon.mod"
$moduleName = Require-Match $moduleText '^name\s*=\s*"(?<value>[^"]+)"' "module name"
$version = Require-Match $moduleText '^version\s*=\s*"(?<value>[^"]+)"' "module version"
$webPackage = (Read-Text "web/package.json") | ConvertFrom-Json
$webDemo = Read-Text "cmd/web_demo/main.mbt"
$readme = Read-Text "README.md"
$changelog = Read-Text "CHANGELOG.md"

if ($webPackage.version -cne $version) {
  throw "web/package.json version $($webPackage.version) does not match moon.mod $version."
}
if (-not $webDemo.Contains("version: `"$version`"")) {
  throw "cmd/web_demo/main.mbt does not expose version $version."
}
if (-not $readme.Contains("moon add $moduleName@$version")) {
  throw "README installation command does not use $moduleName@$version."
}
if (-not $changelog.Contains("## $version -")) {
  throw "CHANGELOG.md has no release heading for $version."
}

$minimumText = Require-Match $readme 'requires MoonBit `(?<value>\d+\.\d+\.\d+)` or newer' "minimum MoonBit version"
$minimum = [version]$minimumText
$requiredFloor = [version]"0.10.16"
if ($minimum -lt $requiredFloor) {
  throw "Documented MoonBit floor $minimum is below required floor $requiredFloor."
}

$workflowText = (Read-Text ".github/workflows/ci.yml") + "`n" +
  (Read-Text ".github/workflows/pages.yml")
$pins = @([regex]::Matches($workflowText, '(?:core-)?version:\s*(?<value>\d+\.\d+\.\d+\+[0-9a-f]+)') |
  ForEach-Object { $_.Groups["value"].Value } |
  Sort-Object -Unique)
if ($pins.Count -ne 1) {
  throw "CI and Pages must use one exact MoonBit toolchain pin; found: $($pins -join ', ')."
}
$pin = $pins[0]
$pinVersion = [version](($pin -split '\+', 2)[0])
if ($pinVersion -lt $minimum) {
  throw "CI toolchain $pin is below documented minimum $minimum."
}
$verifiedPattern = 'verified\s+with MoonBit `' + [regex]::Escape($pin) + '`'
if ($readme -notmatch $verifiedPattern) {
  throw "README does not record verification with the CI toolchain $pin."
}

$compilerOutput = (& moonc -v 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $compilerOutput -notmatch 'v(?<value>\d+\.\d+\.\d+)') {
  throw "Could not read installed moonc version: $compilerOutput"
}
$installed = [version]$Matches["value"]
if ($installed -lt $minimum) {
  throw "Installed moonc $installed is below documented minimum $minimum."
}

Write-Host "Release metadata gate passed: $moduleName@$version, moonc floor $minimum, CI $pin."

