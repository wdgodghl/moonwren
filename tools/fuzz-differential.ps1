param(
  [Parameter(Mandatory = $true)]
  [string]$OfficialWren,

  [string]$MoonWren,

  [ValidateRange(1, 10000)]
  [int]$Cases = 200,

  [int]$Seed = 20261025
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $MoonWren) {
  $MoonWren = Join-Path $projectRoot "_build/native/debug/build/cmd/main/main.exe"
}
foreach ($executable in @($OfficialWren, $MoonWren)) {
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Executable not found: $executable"
  }
}

$random = [System.Random]::new($Seed)
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("moonwren-fuzz-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $temporaryRoot)

function Invoke-WrenProgram {
  param([string]$Executable, [string]$Path)
  $output = & $Executable $Path 2>&1
  [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = (($output | ForEach-Object { $_.ToString() }) -join "`n").TrimEnd()
  }
}

try {
  for ($index = 0; $index -lt $Cases; $index++) {
    $a = $random.Next(-1000, 1001)
    $b = $random.Next(-1000, 1001)
    $limit = $random.Next(1, 30)
    $source = @"
var a = $a
var b = $b
var total = 0
var index = 0
while (index < $limit) {
  total = total + (a * 3 - b * 2 + index)
  index = index + 1
}
System.print(total)
System.print((a < b) || (total == 0))
"@
    $path = Join-Path $temporaryRoot ("case-{0:D5}.wren" -f $index)
    [System.IO.File]::WriteAllText($path, $source)
    $official = Invoke-WrenProgram -Executable $OfficialWren -Path $path
    $candidate = Invoke-WrenProgram -Executable $MoonWren -Path $path
    if ($official.ExitCode -ne $candidate.ExitCode -or $official.Output -ne $candidate.Output) {
      throw "Differential mismatch in case $index (seed $Seed).`nSource:`n$source`nOfficial:`n$($official.Output)`nMoonWren:`n$($candidate.Output)"
    }
  }
  Write-Host "Differential fuzzing passed: $Cases cases (seed $Seed)."
}
finally {
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}
