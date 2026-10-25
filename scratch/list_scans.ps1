$raw = Get-Content "data/scans.js" -Raw -Encoding UTF8
$idx = $raw.IndexOf("[")
$lastIdx = $raw.LastIndexOf("]")
$json = $raw.Substring($idx, $lastIdx - $idx + 1)
$data = ConvertFrom-Json $json
Write-Host "Scans count: $($data.Count)"
foreach ($d in $data) {
    Write-Host "  Date: $($d.date), Rows: $($d.rows.Count)"
}
