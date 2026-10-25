$headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36" }

# Let's inspect all filters on dtdd
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 10 -UseBasicParsing

# Find all links on dtdd that start with /dtdd
$allDtddLinks = [regex]::Matches($r.Content, 'href="(/dtdd[^"]*)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

Write-Host "Total unique /dtdd links on main page: $($allDtddLinks.Count)"
$productLinks = $allDtddLinks | Where-Object { $_ -notmatch '(?i)(?:#|\?|apple|samsung|oppo|xiaomi|vivo|realme|honor|nokia|tcl|infinix|tecno)' }
Write-Host "Direct product-like links on main page: $($productLinks.Count)"

# Also let's check variant links in all cards on main page
$variantMatches = [regex]::Matches($r.Content, '<a[^>]*href="(/dtdd/[^"?#]+)"[^>]*>([0-9]+\s*(?:GB|TB))</a>')
Write-Host "Variant pills matching pattern: $($variantMatches.Count)"
$variantMatches | Select-Object -First 10 | ForEach-Object { Write-Host "  Pill: $($_.Groups[2].Value) -> $($_.Groups[1].Value)" }
