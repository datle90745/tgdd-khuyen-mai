$headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36" }
$hubs = @("dtdd", "dtdd-apple-iphone", "dtdd-samsung", "dtdd-oppo", "dtdd-xiaomi", "dtdd-vivo", "dtdd-realme")
foreach ($h in $hubs) {
    $u = "https://www.thegioididong.com/$h"
    $r = Invoke-WebRequest -Uri $u -Headers $headers -TimeoutSec 10 -UseBasicParsing
    $c1 = ([regex]::Matches($r.Content, '<div data-product-code="')).Count
    $c2 = ([regex]::Matches($r.Content, 'href="(/dtdd/[^"?#]+)"')).Count
    $c3 = ([regex]::Matches($r.Content, '<img aria-label="([^"]+)"')).Count
    Write-Host "$u -> data-product-code: $c1, dtdd-hrefs: $c2, aria-label: $c3"
}
