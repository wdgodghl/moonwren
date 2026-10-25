$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
  moon build --target js cmd/web_demo
  $artifact = Get-ChildItem -LiteralPath (Join-Path $projectRoot "_build/js") -Recurse -File -Filter "web_demo.js" | Select-Object -First 1
  if (-not $artifact) {
    throw "MoonBit did not produce web_demo.js"
  }
  Copy-Item -LiteralPath $artifact.FullName -Destination (Join-Path $projectRoot "web/moonwren.js") -Force
  Write-Host "Browser demo built at web/index.html"
}
finally {
  Pop-Location
}
