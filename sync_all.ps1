$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
$root = $PSScriptRoot
Set-Location $root

$python = Get-Command py -ErrorAction SilentlyContinue
if ($python) {
    $pythonExe = $python.Source
    $pythonArgs = @('-3')
} else {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        $bundledPython = 'C:\Program Files\WindowsApps\OpenAI.CodexPrimaryRuntime.v26-1104-2876-0_26.1104.2876.0_x64__3k8sg7r9htsxt\dependencies\python\python.exe'
        if (-not (Test-Path $bundledPython)) { throw 'Can cai Python 3 va scraper/requirements.txt truoc khi quet tren may.' }
        $pythonExe = $bundledPython
    } else {
        $pythonExe = $python.Source
    }
    $pythonArgs = @()
}

$localDeps = Join-Path $root '.deps'
if (Test-Path $localDeps) {
    $env:PYTHONPATH = $localDeps + [IO.Path]::PathSeparator + $env:PYTHONPATH
}
& $pythonExe @pythonArgs -c 'import requests, bs4, playwright'
if ($LASTEXITCODE -ne 0) { throw 'Thieu thu vien Python. Chay: python -m pip install -r scraper/requirements.txt' }

function Invoke-PythonStep([string]$script) {
    & $pythonExe @pythonArgs $script
    if ($LASTEXITCODE -ne 0) { throw "$script that bai (exit $LASTEXITCODE); khong dong goi/khong day du lieu." }
}

Write-Host '[1/5] Quet TGDĐ theo scraper Python hien hanh...'
Invoke-PythonStep 'scraper/scan_tgdd.py'
Write-Host '[2/5] Quet toan thi truong...'
Invoke-PythonStep 'scraper/scan_market.py'
Write-Host '[3/5] Kiem dinh du lieu moi...'
& node tests/verify_scan.js
if ($LASTEXITCODE -ne 0) { throw 'Circuit breaker that bai; khong dong goi/khong day du lieu.' }
Write-Host '[4/5] Cap nhat cache va dong goi offline...'
$tag = 'sync_' + (Get-Date).ToString('yyyyMMdd_HHmm')
$htmlPath = Join-Path $root 'index.html'
$html = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)
$html = [regex]::Replace($html, '\?v=[^" ]+', "?v=$tag")
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding $false))
Invoke-PythonStep 'scraper/bundle.py'
Write-Host '[5/5] Kiem dinh toan he thong...'
& powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1
if ($LASTEXITCODE -ne 0) { throw 'verify-system.ps1 that bai; khong duoc day du lieu.' }
Write-Host 'Hoan tat dong bo va kiem dinh.'
