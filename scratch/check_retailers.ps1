$mktTxt = [System.IO.File]::ReadAllText("data/market.js", [System.Text.Encoding]::UTF8)
$mMatch = [regex]::Match($mktTxt, '(?s)window\.MARKET\s*=\s*(\{.*?\});')
$mkt = $mMatch.Groups[1].Value | ConvertFrom-Json
$lastScan = $mkt.scans[-1]

$retailers = $lastScan.rows | Select-Object -ExpandProperty r -Unique
Write-Host "Retailers in latest scan:"
$retailers | ForEach-Object { Write-Host " - '$_'" }

$report = $lastScan.report
Write-Host "Report keys:"
$report.PSObject.Properties | ForEach-Object { Write-Host " - '$($_.Name)': $($_.Value)" }
