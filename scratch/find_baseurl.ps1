$headers = @{ "User-Agent" = "Mozilla/5.0" }
$url = "https://cdnv2-tmdt.tgdd.vn/webmwg/production-fe/tmdt-tgdd/_next/static/chunks/3411-988c0a76128cbeba.js"
$js = (Invoke-WebRequest -Uri $url -Headers $headers -TimeoutSec 15 -UseBasicParsing).Content

$idx = $js.IndexOf("https://api.thegioididong.")
while ($idx -ge 0) {
    Write-Host "FOUND AT $idx :"
    Write-Host $js.Substring([Math]::Max(0, $idx - 50), [Math]::Min(300, $js.Length - $idx + 50))
    $idx = $js.IndexOf("https://api.thegioididong.", $idx + 1)
}
