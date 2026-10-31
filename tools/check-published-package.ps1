param(
  [string]$Version,
  [switch]$KeepTemporaryProject,
  [switch]$SkipCliInstall
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not $Version) {
  $manifest = Get-Content (Join-Path $projectRoot "moon.mod") -Raw
  $match = [regex]::Match($manifest, '(?m)^version\s*=\s*"([^"]+)"')
  if (-not $match.Success) { throw "moon.mod does not declare a version." }
  $Version = $match.Groups[1].Value
}
if ($Version -notmatch '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') {
  throw "Invalid semantic version: $Version"
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("moonwren-consumer-" + [guid]::NewGuid().ToString("N"))
$consumer = Join-Path $temporaryRoot "consumer"
$module = "wdgodghl/moonwren@$Version"

function Invoke-Checked {
  param([string]$Name, [scriptblock]$Action)
  Write-Host "== $Name =="
  $global:LASTEXITCODE = 0
  & $Action
  if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE." }
}

New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
  Invoke-Checked "Create an unrelated consumer project" {
    moon new $consumer --user acceptance --name consumer
  }
  Push-Location $consumer
  try {
    Invoke-Checked "Resolve $module from Mooncakes" { moon add $module }

    $dependencyManifest = Get-Content "moon.mod" -Raw
    if (-not $dependencyManifest.Contains("$module")) {
      throw "The consumer manifest did not resolve the requested immutable version $module."
    }

    $packageManifest = @'
import {
  "wdgodghl/moonwren" @moonwren,
}

pkgtype(kind: "executable")
'@
    $program = @'
fn no_modules(_importer : String, name : String) -> @moonwren.ModuleLoadResult {
  @moonwren.ModuleLoadFailed("module '\{name}' is not available")
}

fn completed_value(result : @moonwren.ProgramRunResult) -> String {
  match result {
    @moonwren.ProgramCompleted(value, _) => value.to_text()
    @moonwren.ProgramFailed(issues, _) => abort(issues[0].message)
  }
}

fn main {
  match @moonwren.run("System.print(40 + 2)") {
    @moonwren.ProgramCompleted(_, output) => println("library:\{output[0]}")
    @moonwren.ProgramFailed(issues, _) => abort(issues[0].message)
  }
  match @moonwren.run("var =") {
    @moonwren.ProgramCompleted(_, _) => abort("invalid source unexpectedly succeeded")
    @moonwren.ProgramFailed(issues, _) => println("diagnostic:\{issues[0].message}")
  }

  let vm = @moonwren.Vm::new(@moonwren.VmLimits::standard(100000), no_modules, [], [])
  ignore(vm.interpret("main", "var count = 40\nvar next = Fn.new { count = count + 1 }"))
  match vm.capture("main", "next") {
    @moonwren.VmHandleFailed(issue) => abort(issue.message)
    @moonwren.VmHandleCreated(next) => {
      println("vm:\{completed_value(vm.call(next, []))}")
      println("vm:\{completed_value(vm.call(next, []))}")
    }
  }
  vm.close()
}
'@
    [IO.File]::WriteAllText((Join-Path $consumer "cmd/main/moon.pkg"), $packageManifest, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $consumer "cmd/main/main.mbt"), $program, [Text.UTF8Encoding]::new($false))

    Invoke-Checked "Check the consumer against the registry package" { moon check --target all --deny-warn }
    Write-Host "== Run the documented consumer path =="
    $actual = (& moon run cmd/main 2>&1 | Out-String).Replace("`r`n", "`n").Trim()
    if ($LASTEXITCODE -ne 0) { throw "Consumer run failed:`n$actual" }
    $expected = @"
library:42
diagnostic:expected variable name
vm:41
vm:42
"@.Replace("`r`n", "`n").Trim()
    if ($actual -cne $expected) {
      throw "Consumer output mismatch.`nEXPECTED:`n$expected`nACTUAL:`n$actual"
    }
  } finally {
    Pop-Location
  }

  if (-not $SkipCliInstall) {
    $binaryDirectory = Join-Path $temporaryRoot "bin"
    New-Item -ItemType Directory -Path $binaryDirectory | Out-Null
    Invoke-Checked "Install the published native CLI" {
      moon install "wdgodghl/moonwren/cmd/main@$Version" --bin $binaryDirectory
    }
    $binary = Get-ChildItem -LiteralPath $binaryDirectory -File |
      Where-Object { $_.Name -in @("main", "main.exe") } |
      Select-Object -First 1
    if (-not $binary) { throw "moon install completed without producing the CLI binary." }
    $cliOutput = (& $binary.FullName --eval "System.print(40 + 2)" 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $cliOutput -cne "42") {
      throw "Installed CLI acceptance failed. Output: $cliOutput"
    }
  }

  Write-Host "Published package acceptance passed for $module from outside the repository."
} finally {
  if ($KeepTemporaryProject) {
    Write-Host "Temporary consumer retained at $temporaryRoot"
  } elseif (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}
