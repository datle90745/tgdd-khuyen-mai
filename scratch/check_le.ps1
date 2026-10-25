$text = [System.IO.File]::ReadAllText((Resolve-Path "scraper/scan_market.py").Path)
Write-Host "Contains CRLF:" $text.Contains("`r`n")
Write-Host "Contains LF:" $text.Contains("`n")
