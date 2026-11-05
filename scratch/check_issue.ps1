$content = [System.IO.File]::ReadAllText("$PSScriptRoot/../data/market.js", [System.Text.Encoding]::UTF8)
$prefix = "window.MARKET = "
if ($content.StartsWith("/*")) {
    $idx = $content.IndexOf("window.MARKET = ")
    if ($idx -ge 0) {
        $content = $content.Substring($idx + $prefix.Length)
    }
}
$content = $content.Trim()
if ($content.EndsWith(";")) {
    $content = $content.Substring(0, $content.Length - 1).Trim()
}

$data = ConvertFrom-Json $content
Write-Host "Total scans:" $data.scans.Count
$lastScan = $data.scans[-1]
Write-Host "Last scan: $($lastScan.date) $($lastScan.at)"
Write-Host "Report: $($lastScan.report | ConvertTo-Json -Compress)"
$a17Rows = $lastScan.rows | Where-Object { $_.n -like '*A17*' }
foreach ($r in $a17Rows) {
    Write-Host "$($r.r) | $($r.b) | $($r.n) | p=$($r.p) | o=$($r.o) | url=$($r.u)"
}
