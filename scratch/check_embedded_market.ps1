$c = [System.IO.File]::ReadAllText("$PSScriptRoot/../promotion tgdd.html", [System.Text.Encoding]::UTF8)
$m = [regex]::Match($c, 'window\.MARKET\s*=\s*(\{.*?\});\s*<\/script>')
if ($m.Success) {
    $data = ConvertFrom-Json $m.Groups[1].Value
    Write-Host "Scans in promotion tgdd.html:" $data.scans.Count
    $lastScan = $data.scans[-1]
    Write-Host "Latest scan in promotion tgdd.html:" $lastScan.date $lastScan.at
    $a17 = $lastScan.rows | Where-Object { $_.n -like "*A17 8GB*" }
    foreach ($r in $a17) {
        Write-Host "$($r.r) | $($r.n) | p=$($r.p)"
    }
} else {
    Write-Host "No match for window.MARKET in promotion tgdd.html"
}
