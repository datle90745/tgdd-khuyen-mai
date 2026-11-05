$dataTxt = [System.IO.File]::ReadAllText("data/data.js", [System.Text.Encoding]::UTF8)
$mktTxt = [System.IO.File]::ReadAllText("data/market.js", [System.Text.Encoding]::UTF8)

$bMatch = [regex]::Match($dataTxt, '(?s)window\.BASE\s*=\s*(\{.*?\});\s*(?:window\.|$)')
$base = $bMatch.Groups[1].Value | ConvertFrom-Json

$mMatch = [regex]::Match($mktTxt, '(?s)window\.MARKET\s*=\s*(\{.*?\});')
$mkt = $mMatch.Groups[1].Value | ConvertFrom-Json
$lastScan = $mkt.scans[-1]

function mkKey($s) {
    $str = [string]$s
    $str = $str.ToLower()
    $str = $str.Normalize([System.Text.NormalizationForm]::FormD)
    $str = [regex]::Replace($str, '[\u0300-\u036f]', '')
    $str = $str.Replace([char]0x0111, 'd').Replace([char]0x0110, 'd')
    $str = [regex]::Replace($str, '(\d+)\+(\d+)', '$1gb$2')
    $str = [regex]::Replace($str, '(\d+)\/(\d+)g\b', '$1gb$2gb')
    $str = $str.Replace('+', 'plus')
    $str = [regex]::Replace($str, '\b(dien thoai|samsung|galaxy|xiaomi|oppo|vivo|realme|apple|chinh hang|4g|lte|nfc)\b', ' ')
    $str = [regex]::Replace($str, '\b(titan|xam|den|trang|xanh|vang|bac|hong|tim|gold|silver|black|white|blue|green|purple|pink|grey|gray)\b', ' ')
    $str = [regex]::Replace($str, '[^a-z0-9]', '')
    return $str
}

$mkMap = @{}
foreach ($x in $lastScan.rows) {
    $k = "$($x.r)|$($x.b.ToLower())|$(mkKey $x.n)"
    if (!$mkMap.ContainsKey($k) -or ($x.p -and (!$mkMap[$k].p -or $x.p -lt $mkMap[$k].p))) {
        $mkMap[$k] = $x
    }
}

$target = $base.rows | Where-Object { $_.model -like "*A18*" -or $_.model -like "*A17*" }
foreach ($r in $target) {
    $k = "$($r.brand.ToLower())|$(mkKey $r.model)"
    $tgdd = $mkMap["TGDĐ|$k"]
    $cps  = $mkMap["CellphoneS|$k"]
    $fpt  = $mkMap["FPT Shop|$k"]
    $vt   = $mkMap["Viettel Store|$k"]

    [pscustomobject]@{
        model = $r.model
        channel = $r.channel
        tgdd = if ($tgdd) { $tgdd.p } else { "-" }
        cps = if ($cps) { $cps.p } else { "-" }
        fpt = if ($fpt) { $fpt.p } else { "-" }
        vt = if ($vt) { $vt.p } else { "-" }
        cps_name = if ($cps) { $cps.n } else { "" }
        fpt_name = if ($fpt) { $fpt.n } else { "" }
        vt_name = if ($vt) { $vt.n } else { "" }
    } | Format-List
}
