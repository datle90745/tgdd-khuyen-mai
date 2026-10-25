$path = (Resolve-Path "scraper/scan_market.py").Path
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
Write-Host "Re-encoded scraper/scan_market.py to UTF-8 without BOM."
