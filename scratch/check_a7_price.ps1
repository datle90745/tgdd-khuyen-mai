$headers = @{ "User-Agent" = "Mozilla/5.0" }
$r = Invoke-WebRequest -Uri "https://www.thegioididong.com/dtdd/oppo-a7-pro-5g-6gb-256gb" -Headers $headers -TimeoutSec 10 -UseBasicParsing

# Look for price
$m = [regex]::Matches($r.Content, '.{0,50}(?:14\.490|12\.990|1\.500\.000).{0,50}')
Write-Host "Price matches in page: $($m.Count)"
$m | ForEach-Object { Write-Host "  $($_.Value)" }
