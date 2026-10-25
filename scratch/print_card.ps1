$headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36" }
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 10 -UseBasicParsing

$parts = $r.Content -split '<div data-product-code="'
Write-Host "Total parts: $($parts.Count)"
if ($parts.Count -gt 1) {
    Write-Host "--- CARD 1 FULL CONTENT ---"
    Write-Host $parts[1]
}
