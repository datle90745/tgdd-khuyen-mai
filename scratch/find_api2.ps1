$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/9439-a472554b0e51546b.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

# Search for GET_PRODUCT_CATE_V2
$matches = [regex]::Matches($js, '.{0,100}GET_PRODUCT_CATE_V2.{0,100}')
$matches | ForEach-Object { Write-Host "MATCH: $($_.Value)" }

# Search for module 24661
$url2 = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/3411-988c0a76128cbeba.js"
$js2 = (Invoke-WebRequest -Uri $url2 -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content
$matches2 = [regex]::Matches($js2, '.{0,100}GET_PRODUCT_CATE_V2.{0,100}')
$matches2 | ForEach-Object { Write-Host "MATCH2: $($_.Value)" }
