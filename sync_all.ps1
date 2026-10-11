[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=========================================================="
Write-Host "   BAT DAU DONG BO TOAN BO HE THONG (ALL TABS) CHO HOM NAY"
Write-Host "=========================================================="

# 1. Quet qua tang & khuyen mai chi tiet TGDD (promos.js)
Write-Host ""
Write-Host "[1/3] Quet khuyen mai qua tang TGDD..."
& (Join-Path $ROOT "build_promos.ps1")

# 2. Quet toan thi truong 4 san (market.js, alerts.js, rises.js, fpt.js)
Write-Host ""
Write-Host "[2/3] Quet toan thi truong 4 san ban le lon..."
& (Join-Path $ROOT "build_market.ps1")

# 3. Cap nhat Cache Buster trong index.html
Write-Host ""
Write-Host "[3/4] Cap nhat Cache Buster..."
$now = Get-Date
$tag = "sync_" + $now.ToString("yyyyMMdd_HHmm")
$htmlPath = Join-Path $ROOT "index.html"
$html = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)
$html = [regex]::Replace($html, '\?v=[^"]+', "?v=$tag")
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding $false))

# 4. Dong goi file offline standalone
Write-Host ""
Write-Host "[4/4] Dong goi file offline..."
& (Join-Path $ROOT "bundle_offline.ps1")

Write-Host ""
Write-Host "=========================================================="
& (Join-Path $ROOT "verify_all.ps1")
Write-Host "=========================================================="
Write-Host "HOAN TAT! MOI TAB TRANH LECH DU LIEU VA DA DONG BO 100%!"
