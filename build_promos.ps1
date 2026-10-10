[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$linksRaw = Get-Content "data\links.js" -Raw -Encoding UTF8
$linksJson = $linksRaw.Substring($linksRaw.IndexOf("{"))
$linksJson = $linksJson.Substring(0, $linksJson.LastIndexOf("}") + 1)
$links = $linksJson | ConvertFrom-Json

$keys = @($links.PSObject.Properties.Name)
Write-Host "Bat dau cao qua tang & khuyen mai TGDĐ cho $($keys.Count) SKU..."

function Clean-PromoText($t) {
    if (!$t) { return "" }
    $s = [System.Net.WebUtility]::HtmlDecode($t).Trim()
    $s = [System.Text.RegularExpressions.Regex]::Replace($s, "^(?:\d+[\.\s\-\:]+|[•\-\*]\s*)", "")
    return $s.Trim()
}

function Should-ExcludePromo($s) {
    if (!$s) { return $true }
    $p1 = [regex]::Unescape('\u0111\u1ECDc s\u00E1ch') # doc sach
    $p2 = [regex]::Unescape('l\u1ECDc n\u01B0\u1EDBc') # loc nuoc
    $p3 = [regex]::Unescape('t\u00EDn d\u1EE5ng')     # tin dung
    $p4 = [regex]::Unescape('m\u1EDF th\u1EBB')      # mo the
    if ($s.IndexOf("vpbank", [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($s.IndexOf($p1, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($s.IndexOf($p2, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($s.IndexOf($p3, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($s.IndexOf($p4, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    return $false
}

function Get-TgddPromos($url) {
    if (!$url) { return @() }
    $resArray = C:\Windows\System32\curl.exe -s -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" $url
    $html = $resArray -join "`n"
    if (!$html) { return @() }

    $items = @()
    
    # 1. New Next.js layout spans
    $matches1 = [regex]::Matches($html, '<span class=" \[&amp;_a\]:text-blue-500">([^<]+)</span>')
    foreach ($m in $matches1) {
        $c = Clean-PromoText $m.Groups[1].Value
        if ($c -and !(Should-ExcludePromo $c) -and ($items -notcontains $c)) {
            $items += $c
        }
    }

    # 2. JSON lstGift in streaming RSC
    $matches2 = [regex]::Matches($html, 'lstGift\\":\[\{\\"name\\":\\"([^\\"]+)\\"')
    foreach ($m in $matches2) {
        $c = Clean-PromoText $m.Groups[1].Value
        if ($c -and !(Should-ExcludePromo $c) -and ($items -notcontains $c)) {
            $items += $c
        }
    }

    # 3. Old layout .box-promo or .infopromo li
    $matches3 = [regex]::Matches($html, '(?i)<div[^>]*class="[^"]*content-promo[^"]*"[^>]*>([^<]+)<\/div>')
    foreach ($m in $matches3) {
        $c = Clean-PromoText $m.Groups[1].Value
        if ($c -and !(Should-ExcludePromo $c) -and ($items -notcontains $c)) {
            $items += $c
        }
    }

    return $items
}

$promos = [ordered]@{}
$countWithSubs = 0
$totalItems = 0

$i = 0
foreach ($k in $keys) {
    $i++
    $u = $links.$k
    if (!$u) {
        $promos[$k] = [PSCustomObject]@{ name = $k; subs = @(); offline_note = "" }
        continue
    }

    $subs = Get-TgddPromos $u
    if ($subs.Count -gt 0) {
        $countWithSubs++
        $totalItems += $subs.Count
        Write-Host "[$i/$($keys.Count)] $k -> $($subs.Count) items"
    } else {
        Write-Host "[$i/$($keys.Count)] $k -> 0 items"
    }

    $promos[$k] = [PSCustomObject]@{
        name = $k
        subs = $subs
        offline_note = ""
    }
}

# Fallback ke thua khuyen mai giua cac ban bo nho RAM/ROM cung dong may
foreach ($k in $keys) {
    if ($promos[$k].subs.Count -eq 0) {
        $baseName = [System.Text.RegularExpressions.Regex]::Replace($k, '\s+\d+GB(?:/\d+GB)?.*$', '')
        foreach ($other in $keys) {
            if ($other -ne $k -and $other.StartsWith($baseName) -and $promos[$other].subs.Count -gt 0) {
                $promos[$k].subs = $promos[$other].subs
                $countWithSubs++
                $totalItems += $promos[$k].subs.Count
                Write-Host "Ke thua khuyen mai cho $k tu $other ($($promos[$k].subs.Count) items)"
                break
            }
        }
    }
}

$now = Get-Date -Format "dd-MMM HH:mm"
$promosJson = $promos | ConvertTo-Json -Depth 5 -Compress
$fileContent = "/* Tu dong cao uu dai & qua tang kem tu The Gioi Di Dong */`r`n/* Cap nhat: $now */`r`nwindow.PROMOS = $promosJson;`r`n"
[System.IO.File]::WriteAllText("$PWD\data\promos.js", $fileContent, [System.Text.Encoding]::UTF8)

Write-Host "`nHoan thanh! Da luu data/promos.js:"
Write-Host "- Tong so model: $($keys.Count)"
Write-Host "- So model co khuyen mai/qua tang: $countWithSubs"
Write-Host "- Tong so uu dai ghi nhan: $totalItems"
