$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$BUILD_ID = "1.34.0-wallet-promo-$(Get-Date -Format 'yyyyMMddHHmmss')"
Write-Host "BUILD_ID=$BUILD_ID"

$dist = Join-Path $root 'frontend\dist'
$projectPath = Join-Path $dist '.vercel\project.json'
$projectJson = Get-Content $projectPath -Raw

Get-ChildItem $dist -Exclude '.vercel' | Remove-Item -Recurse -Force
Copy-Item (Join-Path $root 'build\web\*') $dist -Recurse -Force
Copy-Item (Join-Path $root 'frontend\landing\index.html') (Join-Path $dist 'landing.html') -Force
Copy-Item (Join-Path $dist 'index.html') (Join-Path $dist '404.html') -Force
Copy-Item (Join-Path $root 'frontend\middleware.js') (Join-Path $dist 'middleware.js') -Force

New-Item -ItemType Directory -Force -Path (Join-Path $dist '.vercel') | Out-Null
Set-Content -Path $projectPath -Value $projectJson -NoNewline

$buildInfo = @{
  build = $BUILD_ID
  features = @(
    'wallet-promo-codes',
    'dynamic-wallet-checkout',
    'delivered-whatsapp-wallet-code',
    'multi-step-checkout',
    'personal-promo-codes'
  )
} | ConvertTo-Json -Compress
Set-Content -Path (Join-Path $dist 'build-info.json') -Value $buildInfo

foreach ($file in @('index.html', '404.html')) {
  $path = Join-Path $dist $file
  $html = Get-Content $path -Raw
  if ($html -match 'flutter_bootstrap\.js\?v=') {
    $html = [regex]::Replace($html, 'flutter_bootstrap\.js\?v=[^"]+', "flutter_bootstrap.js?v=$BUILD_ID")
  } else {
    $html = $html.Replace('flutter_bootstrap.js', "flutter_bootstrap.js?v=$BUILD_ID")
  }
  Set-Content -Path $path -Value $html -NoNewline
}

node (Join-Path $root 'frontend\scripts\prepareVercelOutput.js')

Set-Content -Path (Join-Path $root '.last_deploy_build_id') -Value $BUILD_ID -NoNewline
Write-Host "Frontend dist prepared: $BUILD_ID"
