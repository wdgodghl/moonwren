param(
  [switch]$SkipInstall,
  [string]$Project,
  [string]$ChromiumChannel
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $projectRoot "web"

Push-Location $projectRoot
try {
  moon build --target js cmd/web_demo
  if ($LASTEXITCODE -ne 0) { throw "Browser build failed." }
  & "$PSScriptRoot/build-web-demo.ps1"
  if ($LASTEXITCODE -ne 0) { throw "Browser artifact assembly failed." }
} finally {
  Pop-Location
}

Push-Location $webRoot
try {
  if (-not $SkipInstall) {
    npm ci
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed." }
  }
  npm test
  if ($LASTEXITCODE -ne 0) { throw "Node SDK smoke tests failed." }
  if ($ChromiumChannel) { $env:PLAYWRIGHT_CHROMIUM_CHANNEL = $ChromiumChannel }
  if ($Project) {
    npm run test:browser -- "--project=$Project"
  } else {
    npm run test:browser
  }
  if ($LASTEXITCODE -ne 0) { throw "Playwright browser acceptance failed." }
} finally {
  Pop-Location
}
