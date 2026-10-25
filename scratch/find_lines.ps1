$lines = [System.IO.File]::ReadAllLines((Resolve-Path "scraper/scan_market.py").Path)
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match 'TGDD_BRAND_HUBS' -or $lines[$i] -match 'def scan_cellphones') {
        Write-Host "Line $i : $($lines[$i])"
    }
}
