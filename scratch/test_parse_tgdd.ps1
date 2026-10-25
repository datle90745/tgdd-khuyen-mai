$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}

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

function Parse-Money($text) {
    if (!$text) { return 0 }
    $digits = [regex]::Replace($text, "[^0-9]", "")
    if ($digits) { return [int64]$digits }
    return 0
}

function Infer-Brand($text) {
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

$seen = [System.Collections.Generic.HashSet[string]]::new()
$products = [System.Collections.Generic.List[object]]::new()

foreach ($u in $urls) {
    try {
        $r = Invoke-WebRequest -Uri $u -Headers $headers -TimeoutSec 10 -UseBasicParsing
        $html = $r.Content
        $parts = $html -split '<div data-product-code="'
        foreach ($p in $parts[1..($parts.Count - 1)]) {
            $linkM = [regex]::Match($p, 'href="(/dtdd/[^"?#]+)"')
            if (!$linkM.Success) { continue }
            $href = $linkM.Groups[1].Value
            if ($seen.Contains($href)) { continue }

            $nameM = [regex]::Match($p, '<img [^>]*alt="([^"]+)"')
            if (!$nameM.Success) { $nameM = [regex]::Match($p, '<a[^>]*title="([^"]+)"') }
            $name = if ($nameM.Success) { [regex]::Replace($nameM.Groups[1].Value, '^Điện thoại\s+', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Trim() } else { "" }

            $brand = Infer-Brand $name
            if (!$brand -or !$name) { continue }

            $priceM = [regex]::Match($p, '<a[^>]*class="[^"]*text-red-7[^"]*"[^>]*><span>([0-9.,]+)[^<]*</span>')
            $delM = [regex]::Match($p, '<del[^>]*>([0-9.,]+)[^<]*</del>')
            $price = if ($priceM.Success) { Parse-Money $priceM.Groups[1].Value } else { 0 }
            $orig = if ($delM.Success) { Parse-Money $delM.Groups[1].Value } else { 0 }

            if ($price -le 0) { continue }
            if ($orig -le $price) { $orig = $price }

            $seen.Add($href) | Out-Null
            $products.Add([PSCustomObject]@{
                Retailer = "TGDĐ"
                Brand = $brand
                Name = $name
                Url = "https://www.thegioididong.com" + $href
                Price = $price
                Orig = $orig
            })
        }
    } catch {
        Write-Host "Error fetching ${u}: $($_.Exception.Message)"
    }
}

Write-Host "Total parsed products from cards: $($products.Count)"

# Check brand breakdown
$products | Group-Object Brand | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Count)"
}
