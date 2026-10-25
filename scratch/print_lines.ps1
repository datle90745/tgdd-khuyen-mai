$lines = [System.IO.File]::ReadAllLines((Resolve-Path "scraper/scan_market.py").Path)
for ($i = 175; $i -le 192; $i++) {
    Write-Host "$i : $($lines[$i])"
}
