$headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36" }

$urls = @(
    "https://www.thegioididong.com/dtdd",
    "https://www.thegioididong.com/dtdd-apple-iphone",
    "https://www.thegioididong.com/dtdd-samsung",
    "https://www.thegioididong.com/dtdd-oppo",
    "https://www.thegioididong.com/dtdd-xiaomi",
    "https://www.thegioididong.com/dtdd-vivo",
    "https://www.thegioididong.com/dtdd-realme",
    "https://www.thegioididong.com/dtdd-honor",
    "https://www.thegioididong.com/dtdd?p=duoi-2-trieu",
    "https://www.thegioididong.com/dtdd?p=tu-2-4-trieu",
    "https://www.thegioididong.com/dtdd?p=tu-4-7-trieu",
    "https://www.thegioididong.com/dtdd?p=tu-7-13-trieu",
    "https://www.thegioididong.com/dtdd?p=tu-13-20-trieu",
    "https://www.thegioididong.com/dtdd?p=tren-20-trieu"
)

$allProductHrefs = [System.Collections.Generic.HashSet[string]]::new()

foreach ($u in $urls) {
    try {
        $r = Invoke-WebRequest -Uri $u -Headers $headers -TimeoutSec 10 -UseBasicParsing
        $matches = [regex]::Matches($r.Content, 'href="(/dtdd/[^"?#]+)"')
        $countBefore = $allProductHrefs.Count
        foreach ($m in $matches) {
            $href = $m.Groups[1].Value
            # Filter out non-product links
            if ($href -notmatch '(?i)(?:dtdd-(?:apple|samsung|oppo|xiaomi|vivo|realme|honor)|#|\?)') {
                $allProductHrefs.Add($href) | Out-Null
            }
        }
        Write-Host "$u -> Added $($allProductHrefs.Count - $countBefore), Total unique: $($allProductHrefs.Count)"
    } catch {
        Write-Host "$u -> Error: $($_.Exception.Message)"
    }
}

Write-Host "`nTotal unique product URLs found across all sources: $($allProductHrefs.Count)"
