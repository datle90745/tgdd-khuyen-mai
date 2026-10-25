$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/app/%5Bcategory%5D/(category)/page-972746e093e6e3ba.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

# Search for "pi=" or "pi:" or fetch
$matches = [regex]::Matches($js, '.{0,100}(?:pi=|pageIndex|pageSize|pi:|\/api\/|listproducts|FilterProduct).{0,100}')
Write-Host "Matches count: $($matches.Count)"
$matches | Select-Object -First 10 | ForEach-Object { Write-Host "MATCH: $($_.Value)" }
