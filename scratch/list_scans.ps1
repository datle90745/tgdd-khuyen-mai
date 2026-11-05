$m = Get-Content 'data/market.js' -Raw -Encoding UTF8
if ($m -match 'window\.MARKET\s*=\s*(\{.*?\});') {
    $j = $matches[1] | ConvertFrom-Json
    foreach ($s in $j.scans) {
        Write-Host "Date: $($s.date) at $($s.at) | Rows: $($s.rows.Count)"
    }
}
