$c = [System.IO.File]::ReadAllText("$PSScriptRoot/../data/market.js", [System.Text.Encoding]::UTF8)
$prefix = "window.MARKET = "
if ($c.StartsWith("/*")) {
    $idx = $c.IndexOf("window.MARKET = ")
    if ($idx -ge 0) {
        $c = $c.Substring($idx + $prefix.Length)
    }
}
$c = $c.Trim()
if ($c.EndsWith(";")) {
    $c = $c.Substring(0, $c.Length - 1).Trim()
}
$data = ConvertFrom-Json $c
$lastScan = $data.scans[-1]
Write-Host "Last scan date:" $lastScan.date $lastScan.at
$retailers = $lastScan.rows | Select-Object -ExpandProperty r -Unique
Write-Host "Unique retailers:" ($retailers -join ", ")

$a17Rows = $lastScan.rows | Where-Object { $_.n -like "*A17*" }
foreach ($row in $a17Rows) {
    Write-Host "$($row.r) | $($row.b) | $($row.n) | p=$($row.p) | o=$($row.o)"
}
