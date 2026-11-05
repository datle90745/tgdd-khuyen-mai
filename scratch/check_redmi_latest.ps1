$lat = Get-Content 'data/latest.js' -Raw -Encoding UTF8
if ($lat -match 'window\.LATEST\s*=\s*(\{.*?\});') {
    $j = $matches[1] | ConvertFrom-Json
    $row = $j.rows | Where-Object { $_.model -eq "Redmi 17 4G 6GB/256GB" }
    Write-Host ($row | ConvertTo-Json)
}
