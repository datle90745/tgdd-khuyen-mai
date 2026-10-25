$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 15 -UseBasicParsing

Write-Host "Contains __NEXT_DATA__: $($r.Content.Contains('__NEXT_DATA__'))"
Write-Host "Contains __next_f: $($r.Content.Contains('__next_f'))"

# Let's search for how products are listed or APIs called
$apis = [regex]::Matches($r.Content, 'https?://[^\s"''<>]*(?:api|product|filter|category)[^\s"''<>]*')
Write-Host "API urls:"
$apis | ForEach-Object { $_.Value } | Select-Object -Unique | Select-Object -First 20
