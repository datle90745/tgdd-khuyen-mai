$ROOT = "$PSScriptRoot/.."
$now = Get-Date
$tag = "sync_" + $now.ToString("yyyyMMdd_HHmm")
$htmlPath = Join-Path $ROOT "index.html"
$html = [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8)
$html = [regex]::Replace($html, '\?v=[^"]+', "?v=$tag")
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Updated Cache Buster to $tag"
