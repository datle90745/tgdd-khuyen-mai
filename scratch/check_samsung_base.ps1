$base = (Get-Content "data/data.js" -Raw -Encoding UTF8)
$match = [regex]::Match($base, 'window\.BASE\s*=\s*(\{.*?\});\s*window\.MASTER_ORDER', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$baseObj = ConvertFrom-Json $match.Groups[1].Value

Write-Host "Total rows in BASE: $($baseObj.rows.Count)"
Write-Host "Samsung rows:"
$baseObj.rows | Where-Object { $_.brand -eq "Samsung" } | ForEach-Object {
    Write-Host "  $($_.model) | $($_.rrp) | $($_.channel) | $($_.segment)"
}
