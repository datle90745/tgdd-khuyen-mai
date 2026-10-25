$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/9439-a472554b0e51546b.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

$idx = $js.IndexOf("getProductCateV2")
Write-Host $js.Substring([Math]::Max(0, $idx - 50), [Math]::Min(500, $js.Length - $idx + 50))
