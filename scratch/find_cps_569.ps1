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

Write-Host "Scans count:" $data.scans.Count
for ($i = 0; $i -lt $data.scans.Count; $i++) {
    $s = $data.scans[$i]
    $cpsA17 = $s.rows | Where-Object { $_.r -eq "CellphoneS" -and $_.n -like "*A17*" }
    foreach ($row in $cpsA17) {
        if ($row.p -eq 5690000 -or $row.o -eq 5690000) {
            Write-Host "FOUND in scan index $i (Date: $($s.date) $($s.at)): $($row.n) p=$($row.p) o=$($row.o)"
        }
    }
}
