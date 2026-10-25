$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/3411-988c0a76128cbeba.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

$idx = $js.IndexOf("83940:")
if ($idx -ge 0) {
    Write-Host $js.Substring($idx, [Math]::Min(1500, $js.Length - $idx))
}
