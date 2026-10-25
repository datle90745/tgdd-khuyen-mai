$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/app/%5Bcategory%5D/(category)/page-972746e093e6e3ba.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

$idx = $js.IndexOf("91565:")
if ($idx -ge 0) {
    Write-Host "Found 91565:"
    Write-Host $js.Substring($idx, [Math]::Min(1200, $js.Length - $idx))
} else {
    Write-Host "91565 not in this file, searching for 'getProductCateV2' definitions"
    $matches = [regex]::Matches($js, '.{0,100}getProductCateV2.{0,200}')
    $matches | ForEach-Object { Write-Host "DEF: $($_.Value)" }
}
