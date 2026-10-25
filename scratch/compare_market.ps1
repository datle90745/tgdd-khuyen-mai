# Read data/market.js
$content = Get-Content "data/market.js" -Raw -Encoding UTF8
$jsonText = $content -replace '^window\.MARKET\s*=\s*', '' -replace ';?\s*$', ''
$market = ConvertFrom-Json $jsonText

$latestScan = $market.scans[-1]
$tgddRows = $latestScan.rows | Where-Object { $_.r -eq "TGDĐ" }
Write-Host "TGDĐ products in market.js latest scan ($($latestScan.date)): $($tgddRows.Count)"

# Check urls in market.js
$marketUrls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $tgddRows) {
    $marketUrls.Add($r.u) | Out-Null
}

# Compare with the 266 URLs collected
$headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36" }
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 10 -UseBasicParsing
$dtddMatches = [regex]::Matches($r.Content, 'href="(/dtdd/[^"?#]+)"') | ForEach-Object { "https://www.thegioididong.com" + $_.Groups[1].Value } | Select-Object -Unique

Write-Host "URLs directly on dtdd main page: $($dtddMatches.Count)"
$missingFromMarket = $dtddMatches | Where-Object { -not $marketUrls.Contains($_) }
Write-Host "Missing from market.js among dtdd main page URLs: $($missingFromMarket.Count)"
Write-Host "First 15 missing:"
$missingFromMarket | Select-Object -First 15
