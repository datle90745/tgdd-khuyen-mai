$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    "Accept-Language" = "vi-VN,vi;q=0.9"
}
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd" -Headers $headers -TimeoutSec 15 -UseBasicParsing

$matches = [regex]::Matches($r.Content, '.{0,50}(?:urlCate|cateId|groupId|productIdList).{0,100}')
$matches | Select-Object -First 10 | ForEach-Object { Write-Host "MATCH: $($_.Value)" }
