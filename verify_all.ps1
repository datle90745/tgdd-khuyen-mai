[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== KIEM TRA DONG BO TOAN BO DU LIEU ==="

# 1. LATEST
$l = [System.IO.File]::ReadAllText("data\latest.js", [System.Text.Encoding]::UTF8)
$lIdx = $l.IndexOf('{'); $lLast = $l.LastIndexOf('}')
$lObj = $l.Substring($lIdx, $lLast - $lIdx + 1) | ConvertFrom-Json
Write-Host "1. Tab TGDD 86 SKU (latest.js):"
Write-Host "   - Ngay: $($lObj.date)"
Write-Host "   - So may: $($lObj.rows.Count)"

# 2. PROMOS
$p = [System.IO.File]::ReadAllText("data\promos.js", [System.Text.Encoding]::UTF8)
$pIdx = $p.IndexOf('{'); $pLast = $p.LastIndexOf('}')
$pObj = $p.Substring($pIdx, $pLast - $pIdx + 1) | ConvertFrom-Json
Write-Host "2. Khuyen mai qua tang (promos.js):"
Write-Host "   - SKU co qua: $($pObj.PSObject.Properties.Name.Count)"

# 3. MARKET
$m = [System.IO.File]::ReadAllText("data\market.js", [System.Text.Encoding]::UTF8)
$mIdx = $m.IndexOf('{'); $mLast = $m.LastIndexOf('}')
$mObj = $m.Substring($mIdx, $mLast - $mIdx + 1) | ConvertFrom-Json
Write-Host "3. Tab Toan thi truong 4 san (market.js):"
foreach ($s in $mObj.scans) {
    Write-Host "   - Dot quet: $($s.date) luc $($s.at) | Tong: $($s.rows.Count) may"
    Write-Host "     Bao cao: $($s.report | ConvertTo-Json -Compress)"
}

# 4. FPT
$f = [System.IO.File]::ReadAllText("data\fpt.js", [System.Text.Encoding]::UTF8)
$fIdx = $f.IndexOf('{'); $fLast = $f.LastIndexOf('}')
$fObj = $f.Substring($fIdx, $fLast - $fIdx + 1) | ConvertFrom-Json
Write-Host "4. FPT Shop cuc bo (fpt.js):"
Write-Host "   - Ngay: $($fObj.date) luc $($fObj.at)"
Write-Host "   - So may: $($fObj.rows.Count)"

# 5. ALERTS
$a = [System.IO.File]::ReadAllText("data\alerts.js", [System.Text.Encoding]::UTF8)
$aIdx = $a.IndexOf('['); $aLast = $a.LastIndexOf(']')
$aObj = $a.Substring($aIdx, $aLast - $aIdx + 1) | ConvertFrom-Json
Write-Host "5. Tab Canh bao tang gia (alerts.js):"
foreach ($e in $aObj) {
    Write-Host "   - [$($e.source)] $($e.day) luc $($e.at): $($e.items.Count) canh bao"
}
