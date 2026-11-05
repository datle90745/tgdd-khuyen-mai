$path = "$PSScriptRoot/../scraper/scan_market.py"
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

# Check occurrences of corrupted TGD
$matches = [regex]::Matches($content, 'TGDA?[^"\s,\)]*')
foreach ($m in $matches) {
    Write-Host "Matched:" $m.Value
}
