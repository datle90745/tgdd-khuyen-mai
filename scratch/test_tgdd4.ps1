$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 15 -UseBasicParsing

# Find keywords in __next_f
$keywords = @("productName", "product_name", "urlSlug", "url_slug", "price", "brandName", "brand_name", "productId", "totalProduct", "total_product")
foreach ($kw in $keywords) {
    $c = ([regex]::Matches($r.Content, "`"$kw`"")).Count
    Write-Host "$kw count: $c"
}

# Find API URLs or endpoints inside __next_f or JS chunks
$m = [regex]::Matches($r.Content, '(/api/[^"'']+|https://[^\s"'']+/api/[^\s"'']+|https://[^\s"'']+/Category[^\s"'']*)')
Write-Host "Internal endpoints:"
$m | ForEach-Object { $_.Value } | Select-Object -Unique | Select-Object -First 20
