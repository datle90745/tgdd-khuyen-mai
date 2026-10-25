$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/app/%5Bcategory%5D/(category)/page-972746e093e6e3ba.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

$idx = $js.IndexOf("getProductCateV2")
if ($idx -ge 0) {
    Write-Host "Context of getProductCateV2:"
    Write-Host $js.Substring([Math]::Max(0, $idx - 300), 800)
}
