$lat = Get-Content 'data/latest.js' -Raw -Encoding UTF8
if ($lat -match 'window\.LATEST\s*=\s*(\{.*?\});') {
    $j = $matches[1] | ConvertFrom-Json
    $a18s = $j.rows | Where-Object { $_.model -like "*A18*" }
    Write-Host ($a18s | ConvertTo-Json)
}
