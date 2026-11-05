$s = Get-Content 'data/latest.js' -Raw -Encoding UTF8
if ($s -match 'window\.LATEST\s*=\s*(\{.*?\});') {
    $j = $matches[1] | ConvertFrom-Json
    Write-Host "LATEST date: $($j.date), count: $($j.rows.Count)"
    $active = ($j.rows | Where-Object { $_.status -eq 'active' }).Count
    Write-Host "Active rows: $active"
    $hasPmh = ($j.rows | Where-Object { $_.pmh -gt 0 }).Count
    Write-Host "Rows with PMH > 0: $hasPmh"
}

$m = Get-Content 'data/market.js' -Raw -Encoding UTF8
if ($m -match 'window\.MARKET\s*=\s*(\{.*?\});') {
    $mj = $matches[1] | ConvertFrom-Json
    $lastScan = $mj.scans[-1]
    Write-Host "MARKET last scan: $($lastScan.date) at $($lastScan.at)"
    Write-Host "TGDD rows in market: $(($lastScan.rows | Where-Object { $_.r -eq 'TGDĐ' }).Count)"
    Write-Host "CellphoneS rows in market: $(($lastScan.rows | Where-Object { $_.r -eq 'CellphoneS' }).Count)"
    Write-Host "FPT Shop rows in market: $(($lastScan.rows | Where-Object { $_.r -eq 'FPT Shop' }).Count)"
    Write-Host "Viettel Store rows in market: $(($lastScan.rows | Where-Object { $_.r -eq 'Viettel Store' }).Count)"
}
