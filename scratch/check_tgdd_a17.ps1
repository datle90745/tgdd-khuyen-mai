$mktTxt = [System.IO.File]::ReadAllText("data/market.js", [System.Text.Encoding]::UTF8)
$mMatch = [regex]::Match($mktTxt, '(?s)window\.MARKET\s*=\s*(\{.*?\});')
$mkt = $mMatch.Groups[1].Value | ConvertFrom-Json
$lastScan = $mkt.scans[-1]

$lastScan.rows | Where-Object { $_.r -eq "TGDĐ" -and $_.n -like "*A17*" } | Select-Object r, b, n, p, o, u | Format-Table -AutoSize
