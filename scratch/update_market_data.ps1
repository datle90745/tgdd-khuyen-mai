$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}

$urls = @(
    @{ url = "https://www.thegioididong.com/dtdd"; brand = "" },
    @{ url = "https://www.thegioididong.com/dtdd-apple-iphone"; brand = "Apple" },
    @{ url = "https://www.thegioididong.com/dtdd-samsung"; brand = "Samsung" },
    @{ url = "https://www.thegioididong.com/dtdd-oppo"; brand = "OPPO" },
    @{ url = "https://www.thegioididong.com/dtdd-xiaomi"; brand = "Xiaomi" },
    @{ url = "https://www.thegioididong.com/dtdd-vivo"; brand = "Vivo" },
    @{ url = "https://www.thegioididong.com/dtdd-realme"; brand = "Realme" },
    @{ url = "https://www.thegioididong.com/dtdd-honor"; brand = "Honor" },
    @{ url = "https://www.thegioididong.com/dtdd?p=duoi-2-trieu"; brand = "" },
    @{ url = "https://www.thegioididong.com/dtdd?p=tu-2-4-trieu"; brand = "" },
    @{ url = "https://www.thegioididong.com/dtdd?p=tu-4-7-trieu"; brand = "" },
    @{ url = "https://www.thegioididong.com/dtdd?p=tu-7-13-trieu"; brand = "" },
    @{ url = "https://www.thegioididong.com/dtdd?p=tu-13-20-trieu"; brand = "" },
    @{ url = "https://www.thegioididong.com/dtdd?p=tren-20-trieu"; brand = "" }
)

function Parse-Money($text) {
    if (!$text) { return 0 }
    $digits = [regex]::Replace($text, "[^0-9]", "")
    if ($digits) { return [int64]$digits }
    return 0
}

function Infer-Brand($text, $hint) {
    if ($hint) { return $hint }
    if (!$text) { return "" }
    if ($text -match '(?i)\b(apple|iphone)\b') { return "Apple" }
    if ($text -match '(?i)\b(samsung|galaxy)\b') { return "Samsung" }
    if ($text -match '(?i)\b(oppo|reno|find)\b') { return "OPPO" }
    if ($text -match '(?i)\b(xiaomi|redmi|poco)\b') { return "Xiaomi" }
    if ($text -match '(?i)\b(vivo)\b') { return "Vivo" }
    if ($text -match '(?i)\b(realme)\b') { return "Realme" }
    if ($text -match '(?i)\b(honor)\b') { return "Honor" }
    return ""
}

$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$tgddRows = [System.Collections.Generic.List[object]]::new()
$unseenVariants = [System.Collections.Generic.List[object]]::new()

Write-Host "Scraping TGDĐ all sources..."
foreach ($item in $urls) {
    $u = $item.url
    $b_hint = $item.brand
    try {
        $r = Invoke-WebRequest -Uri $u -Headers $headers -TimeoutSec 10 -UseBasicParsing
        $html = $r.Content
        $parts = $html -split '<div data-product-code="'
        foreach ($p in $parts[1..($parts.Count - 1)]) {
            $linkM = [regex]::Match($p, 'href="(/dtdd/[^"?#]+)"')
            if (!$linkM.Success) { continue }
            $href = $linkM.Groups[1].Value.Trim()
            $nameM = [regex]::Match($p, '<img [^>]*alt="([^"]+)"')
            if (!$nameM.Success) { $nameM = [regex]::Match($p, '<a[^>]*title="([^"]+)"') }
            $baseName = if ($nameM.Success) { [regex]::Replace($nameM.Groups[1].Value, '^Điện thoại\s+', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Trim() } else { "" }
            $brand = Infer-Brand $baseName $b_hint

            # Extract variant pills
            $vMatches = [regex]::Matches($p, '<a[^>]*href="(/dtdd/[^"?#]+)"[^>]*>([0-9]+\s*(?:GB|TB))</a>')
            foreach ($vm in $vMatches) {
                $vHref = $vm.Groups[1].Value.Trim()
                $vCap = $vm.Groups[2].Value.Trim()
                if (!$seen.Contains($vHref) -and $vHref -ne $href) {
                    $unseenVariants.Add([PSCustomObject]@{ Href = $vHref; ParentName = $baseName; Brand = $brand; Cap = $vCap })
                }
            }

            if ($seen.Contains($href) -or !$brand -or !$baseName) { continue }

            $priceM = [regex]::Match($p, '<a[^>]*class="[^"]*text-red-7[^"]*"[^>]*><span>([0-9.,]+)[^<]*</span>')
            $delM = [regex]::Match($p, '<del[^>]*>([0-9.,]+)[^<]*</del>')
            $price = if ($priceM.Success) { Parse-Money $priceM.Groups[1].Value } else { 0 }
            $orig = if ($delM.Success) { Parse-Money $delM.Groups[1].Value } else { 0 }

            if ($price -le 0) { continue }
            if ($orig -le $price) { $orig = $price }

            $seen.Add($href) | Out-Null
            $tgddRows.Add([PSCustomObject]@{
                r = "TGDĐ"
                b = $brand
                n = $baseName
                u = "https://www.thegioididong.com" + $href
                p = $price
                o = $orig
                k = "Khuyến mãi"
            })
        }
    } catch {
        Write-Host "Error fetching $($u): $($_.Exception.Message)"
    }
}

Write-Host "Primary cards parsed: $($tgddRows.Count)"
Write-Host "Unseen variants to fetch: $($unseenVariants.Count)"

# Fetch variant details for any remaining unseen variants
$vSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($v in $unseenVariants) {
    if ($seen.Contains($v.Href) -or $vSeen.Contains($v.Href)) { continue }
    $vSeen.Add($v.Href) | Out-Null
    try {
        $vUrl = "https://www.thegioididong.com" + $v.Href
        $r = Invoke-WebRequest -Uri $vUrl -Headers $headers -TimeoutSec 10 -UseBasicParsing
        $vHtml = $r.Content
        $titleM = [regex]::Match($vHtml, '<h1[^>]*>([^<]+)</h1>')
        if (!$titleM.Success) { $titleM = [regex]::Match($vHtml, '<title>([^<]+)</title>') }
        $vName = if ($titleM.Success) { [regex]::Replace($titleM.Groups[1].Value, '^Điện thoại\s+', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Trim() } else { "$($v.ParentName) $($v.Cap)" }
        $vBrand = Infer-Brand $vName $v.Brand
        
        $priceM = [regex]::Match($vHtml, 'class="[^"]*(?:bs-price|box-price-present|text-red-7)[^"]*"[^>]*>.*?([0-9.,]{5,12})')
        $delM = [regex]::Match($vHtml, '<del[^>]*>.*?([0-9.,]{5,12})')
        $vPrice = if ($priceM.Success) { Parse-Money $priceM.Groups[1].Value } else { 0 }
        $vOrig = if ($delM.Success) { Parse-Money $delM.Groups[1].Value } else { $vPrice }
        
        if ($vPrice -le 0 -and $vOrig -gt 0) {
            $vPrice = $vOrig
        }
        if ($vPrice -gt 0) {
            $seen.Add($v.Href) | Out-Null
            $tgddRows.Add([PSCustomObject]@{
                r = "TGDĐ"
                b = $vBrand
                n = $vName
                u = $vUrl
                p = $vPrice
                o = if ($vOrig -gt $vPrice) { $vOrig } else { $vPrice }
                k = "Khuyến mãi"
            })
        }
    } catch {}
}

Write-Host "Total TGDĐ rows after variant expansion: $($tgddRows.Count)"

# Read current market.js
$marketRaw = [System.IO.File]::ReadAllText((Resolve-Path "data/market.js").Path, [System.Text.Encoding]::UTF8)
$idx = $marketRaw.IndexOf("{")
$lastIdx = $marketRaw.LastIndexOf("}")
$jsonStr = $marketRaw.Substring($idx, $lastIdx - $idx + 1)
$marketObj = ConvertFrom-Json $jsonStr

# In the scans array, find the latest scan (or 23-Oct scan)
$latestScan = $marketObj.scans[-1]
Write-Host "Updating market.js latest scan: date=$($latestScan.date)"

# Keep non-TGDD rows (CellphoneS, FPT, Viettel)
$nonTgddRows = @($latestScan.rows | Where-Object { $_.r -ne "TGDĐ" })
Write-Host "Non-TGDĐ rows: $($nonTgddRows.Count)"

# Combine all rows
$allRows = @($tgddRows) + @($nonTgddRows)
Write-Host "Combined new scan total rows: $($allRows.Count)"

$latestScan.rows = $allRows
$latestScan.report."TGDĐ" = $tgddRows.Count

# Write back to data/market.js
$newJson = ConvertTo-Json $marketObj -Depth 10 -Compress
$outJs = "/* Tự sinh bởi scraper/scan_market.py, đừng sửa tay. */`nwindow.MARKET = $newJson;"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path "data/market.js").Path, $outJs, $utf8NoBom)
Write-Host "Updated data/market.js successfully! TGDĐ now has $($tgddRows.Count) products."
