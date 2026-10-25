$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/app/%5Bcategory%5D/(category)/page-972746e093e6e3ba.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

$matches = [regex]::Matches($js, '.{0,50}urlCate.{0,100}')
$matches | Select-Object -First 10 | ForEach-Object { Write-Host "MATCH: $($_.Value)" }
