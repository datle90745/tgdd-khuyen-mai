$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/app/%5Bcategory%5D/(category)/page-972746e093e6e3ba.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

# Search around getProductCateV2
$idx = $js.IndexOf("getProductCateV2")
Write-Host $js.Substring([Math]::Max(0, $idx - 200), [Math]::Min(1000, $js.Length - $idx + 200))

$url2 = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/4779-cbd8347937782fae.js"
$js2 = (Invoke-WebRequest -Uri $url2 -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content
$idx2 = $js2.IndexOf("getProductCateV2")
Write-Host "--- In 4779 ---"
Write-Host $js2.Substring([Math]::Max(0, $idx2 - 200), [Math]::Min(1000, $js2.Length - $idx2 + 200))
