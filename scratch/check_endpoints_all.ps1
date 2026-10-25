$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/3411-988c0a76128cbeba.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

$idx = $js.IndexOf("GET_PRODUCT_CATE")
Write-Host $js.Substring([Math]::Max(0, $idx - 300), [Math]::Min(1000, $js.Length - $idx + 300))
