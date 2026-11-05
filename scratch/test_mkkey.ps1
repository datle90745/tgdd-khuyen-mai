function Get-MkKey($s) {
    $norm = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $norm.ToCharArray()) {
        $uc = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c)
        if ($uc -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    $str = $sb.ToString().ToLower()
    $str = $str.Replace("đ", "d")
    $str = [regex]::Replace($str, '(\d+)\+(\d+)', '$1gb$2')
    $str = [regex]::Replace($str, '(\d+)/(\d+)g\b', '$1gb$2gb')
    $str = $str.Replace("+", "plus")
    $str = [regex]::Replace($str, '\b(dien thoai|samsung|galaxy|xiaomi|oppo|vivo|realme|apple|chinh hang|4g|lte|nfc)\b', ' ')
    $str = [regex]::Replace($str, '\b(titan|xam|den|trang|xanh|vang|bac|hong|tim|gold|silver|black|white|blue|green|purple|pink|grey|gray)\b', ' ')
    $str = [regex]::Replace($str, '[^a-z0-9]', '')
    return $str
}

$m1 = "A17 8GB/128GB"
$m2 = "Samsung Galaxy A17 8GB 128GB"
$m3 = "Samsung Galaxy A17 LTE 8GB 128GB"
Write-Host "m1 '$m1' -> $(Get-MkKey $m1)"
Write-Host "m2 '$m2' -> $(Get-MkKey $m2)"
Write-Host "m3 '$m3' -> $(Get-MkKey $m3)"
