$m = Get-Content 'data/market.js' -Raw -Encoding UTF8
if ($m -match 'window\.MARKET\s*=\s*(\{.*?\});') {
    $j = $matches[1] | ConvertFrom-Json
    $scans = $j.scans
    Write-Host "Total scans: $($scans.Count)"
    $last = $scans[-1]
    Write-Host "Last scan: $($last.date) $($last.at)"
    Write-Host "Report: $(ConvertTo-Json $last.report -Compress)"
}
