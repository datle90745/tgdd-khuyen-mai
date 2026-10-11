[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$MARKET_JS = Join-Path $ROOT "data\market.js"
$LAST_JSON = Join-Path $ROOT "data\market_last.json"
$ALERTS_JS = Join-Path $ROOT "data\alerts.js"
$RISES_JS  = Join-Path $ROOT "data\rises.js"
$FPT_JS    = Join-Path $ROOT "data\fpt.js"

$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
$TGDD_NAME = [regex]::Unescape('TGD\u0110')
$KM_NAME   = [regex]::Unescape('Khuy\u1EBFn m\u00E3i')

function Get-MarketBrand($text1, $text2 = "") {
    $s = ("$text1 $text2").ToLower()
    if ($s -match '\b(apple|iphone)\b')      { return "Apple" }
    if ($s -match '\b(samsung|galaxy)\b')    { return "Samsung" }
    if ($s -match '\boppo\b')                { return "OPPO" }
    if ($s -match '\b(xiaomi|redmi|poco)\b') { return "Xiaomi" }
    if ($s -match '\bvivo\b')                { return "Vivo" }
    if ($s -match '\brealme\b')              { return "Realme" }
    return $null
}

function Parse-Money($t) {
    if (!$t) { return 0 }
    $decoded = [System.Net.WebUtility]::HtmlDecode("$t")
    if ($decoded -match '([0-9]{1,3}(?:\.[0-9]{3})+|[0-9]+)') {
        $clean = [regex]::Replace($matches[1], '[^0-9]', '')
        if ($clean) { return [int64]$clean }
    }
    return 0
}

function Parse-Num($t) {
    if (!$t) { return 0 }
    try {
        $val = [double]::Parse("$t", [Globalization.CultureInfo]::InvariantCulture)
        return [int64][Math]::Round($val)
    } catch {
        return 0
    }
}

# --- 1. TGDĐ ---
Write-Host "1/4. Dang quet TGDD..."
$tgddRows = New-Object System.Collections.ArrayList
$tgddSeen = New-Object System.Collections.Generic.HashSet[string]
for ($page = 0; $page -lt 25; $page++) {
    try {
        $resp = Invoke-RestMethod -Method Post -Uri "https://www.thegioididong.com/Category/FilterProductBox?c=42&o=13&pi=$page" `
            -UserAgent $UA `
            -Headers @{ "X-Requested-With"="XMLHttpRequest"; "Referer"="https://www.thegioididong.com/dtdd"; "Accept-Language"="vi-VN,vi;q=0.9" } `
            -ContentType "application/x-www-form-urlencoded; charset=UTF-8" `
            -Body "IsParentCate=False&IsShowCompare=True&prevent=true"
        
        $html = $resp.listproducts
        if (!$html) { break }
        
        $itemMatches = [regex]::Matches($html, '(?s)<li class=" item ajaxed __cate_42"[^>]*>(.*?)</li>')
        if ($itemMatches.Count -eq 0) { break }

        foreach ($im in $itemMatches) {
            $chunk = $im.Groups[1].Value
            $aMatch = [regex]::Match($chunk, '(?s)<a [^>]*class="[^"]*main-contain[^"]*"[^>]*href=[''"]([^''"]+)[''"]([^>]*)>')
            if (!$aMatch.Success) {
                $aMatch = [regex]::Match($chunk, '(?s)<a href=[''"]([^''"]+)[''"]([^>]*class="[^"]*main-contain[^"]*"[^>]*)>')
            }
            if (!$aMatch.Success) { continue }
            $href = $aMatch.Groups[1].Value
            $tag = $aMatch.Groups[0].Value

            $dataName = if ($tag -match 'data-name="([^"]+)"') { $matches[1] } else { "" }
            $dataBrand = if ($tag -match 'data-brand="([^"]+)"') { $matches[1] } else { "" }
            $dataPrice = if ($tag -match 'data-price="([^"]+)"') { $matches[1] } else { "" }

            $name = [System.Net.WebUtility]::HtmlDecode($dataName)
            $name = [regex]::Replace($name, '^\u0110i\u1EC7n tho\u1EA1i\s+', '', 'IgnoreCase').Trim()
            $brand = Get-MarketBrand $dataBrand $name
            $urlKey = $href.Split("?")[0]
            if (!$brand -or !$tgddSeen.Add($urlKey)) { continue }

            $price = Parse-Num $dataPrice
            if ($price -le 0) { continue }

            $oldMatch = [regex]::Match($chunk, '<p class="price-old[^"]*">([^<]+)</p>')
            $orig = if ($oldMatch.Success) { Parse-Money $oldMatch.Groups[1].Value } else { 0 }
            if ($orig -lt $price) { $orig = $price }

            $kind = if ($href -match 'utm_flashsale=1') { "Flash Sale Online" } else { $KM_NAME }
            [void]$tgddRows.Add([pscustomobject]@{
                r = $TGDD_NAME; b = $brand; n = $name; u = "https://www.thegioididong.com" + $urlKey
                p = $price; o = $orig; k = $kind
            })
        }
        Start-Sleep -Milliseconds 200
    } catch {
        Write-Host "  TGDD page $page dung lai: $_"
        break
    }
}
Write-Host "  TGDD hoan tat: $($tgddRows.Count) may"

# --- 2. CellphoneS ---
Write-Host "2/4. Dang quet CellphoneS..."
$cpsRows = New-Object System.Collections.ArrayList
$cpsTemplate = @'
query { products(filter:{static:{categories:["3"],province_id:30,stock:{from:0},stock_available_id:[46],filter_price:{from:0,to:200000000}},dynamic:{}}, page:{0}, size:100, sort:[{view:desc}]) { general{ name url_path manufacturer } filterable{ price special_price } } }
'@
for ($page = 1; $page -le 10; $page++) {
    try {
        $q = $cpsTemplate.Replace("{0}", "$page")
        $body = @{ query = $q; variables = @{} } | ConvertTo-Json
        $resp = Invoke-RestMethod -Method Post -Uri "https://api.cellphones.com.vn/v2/graphql/query" `
            -UserAgent $UA -ContentType "application/json" -Body $body
        $items = $resp.data.products
        if (!$items -or $items.Count -eq 0) { break }
        foreach ($it in $items) {
            $g = $it.general
            $f = $it.filterable
            $rawName = if ($g.name) { [regex]::Replace($g.name, '\s*\|.*$', '').Trim() } else { "" }
            $brand = Get-MarketBrand $g.manufacturer $rawName
            $orig = Parse-Num $f.price
            $special = Parse-Num $f.special_price
            $price = if ($special -gt 0) { $special } else { $orig }
            if ($brand -and $price -gt 0) {
                $o = if ($orig -gt $price) { $orig } else { $price }
                [void]$cpsRows.Add([pscustomobject]@{
                    r = "CellphoneS"; b = $brand; n = $rawName; u = "https://cellphones.com.vn/" + $g.url_path
                    p = $price; o = $o; k = $KM_NAME
                })
            }
        }
        if ($items.Count -lt 100) { break }
        Start-Sleep -Milliseconds 200
    } catch {
        Write-Host "  CPS page $page dung lai: $_"
        break
    }
}
Write-Host "  CellphoneS hoan tat: $($cpsRows.Count) may"

# --- 3. FPT Shop ---
Write-Host "3/4. Dang quet truc tiep FPT Shop (LIVE)..."
$fptScript = Join-Path $ROOT "scraper\quet_fpt.ps1"
if (Test-Path $fptScript) {
    try {
        & $fptScript -Out $FPT_JS
    } catch {
        Write-Host "  Quet truc tiep FPT loi: $_"
    }
}
$fptRows = New-Object System.Collections.ArrayList
if (Test-Path $FPT_JS) {
    try {
        $fptTxt = [System.IO.File]::ReadAllText($FPT_JS, [System.Text.Encoding]::UTF8)
        $idx = $fptTxt.IndexOf('{')
        $last = $fptTxt.LastIndexOf('}')
        if ($idx -ge 0 -and $last -gt $idx) {
            $fptObj = $fptTxt.Substring($idx, $last - $idx + 1) | ConvertFrom-Json
            $todayLabel = (Get-Date).ToString("dd-MMM", [Globalization.CultureInfo]::InvariantCulture)
            # Chi lay du lieu neu fpt.js duoc quet dung ngay hom nay
            if ($fptObj.date -eq $todayLabel -and $fptObj.rows -and $fptObj.rows.Count -gt 0) {
                foreach ($r in $fptObj.rows) {
                    [void]$fptRows.Add([pscustomobject]@{
                        r = "FPT Shop"
                        b = $r.b
                        n = $r.n
                        u = $r.u
                        p = [int64]$r.p
                        o = [int64]$r.o
                        k = if ($r.k) { $r.k } else { $KM_NAME }
                    })
                }
            } else {
                Write-Host "  Canh bao: data/fpt.js la ngay $($fptObj.date) (khac hom nay $todayLabel), bo qua de dam bao nguyen tac du lieu sach!"
            }
        }
    } catch {
        Write-Host "  Doc fpt.js that bai: $_"
    }
}
Write-Host "  FPT Shop hoan tat: $($fptRows.Count) may"

# --- 4. Viettel Store ---
Write-Host "4/4. Dang quet Viettel Store..."
$vtRows = New-Object System.Collections.ArrayList
$vtSeen = New-Object System.Collections.Generic.HashSet[string]
for ($page = 1; $page -le 8; $page++) {
    try {
        $body = "path=ProductList5Col2026&PaginationVisiable=0&CatID=010001&ManID=&Tags=&PageSize=100&CurrentPage=$page&SpecOrder=DangHot&SpecFilter=&FeatureFilter=&PriceFrom=-1&PriceTo=-1&isHot="
        $resp = Invoke-WebRequest -Method Post -Uri "https://viettelstore.vn/Site/_Sys/GetUserControlAsync.aspx" `
            -UserAgent $UA -UseBasicParsing `
            -ContentType "application/x-www-form-urlencoded; charset=UTF-8" `
            -Headers @{ "X-Requested-With"="XMLHttpRequest"; "Referer"="https://viettelstore.vn/dien-thoai" } `
            -Body $body -TimeoutSec 20
        
        $content = $resp.Content
        $parts = $content -split 'class="product-info-container'
        if ($parts.Count -le 1) { break }

        $pageAdded = 0
        for ($i = 1; $i -lt $parts.Count; $i++) {
            $chunk = $parts[$i]
            $aMatch = [regex]::Match($chunk, '(?s)<a [^>]*href="([^"]+)"[^>]*data-name="([^"]+)"')
            if (!$aMatch.Success) {
                $aMatch = [regex]::Match($chunk, '(?s)<a [^>]*data-name="([^"]+)"[^>]*href="([^"]+)"')
                if (!$aMatch.Success) { continue }
                $rawName = $aMatch.Groups[1].Value
                $href = $aMatch.Groups[2].Value
            } else {
                $href = $aMatch.Groups[1].Value
                $rawName = $aMatch.Groups[2].Value
            }
            $name = [regex]::Replace($rawName, '^\u0110i\u1EC7n tho\u1EA1i\s+', '', 'IgnoreCase').Trim()
            $brand = Get-MarketBrand $name ""
            if (!$brand -or !$vtSeen.Add($href)) { continue }

            $pMatch = [regex]::Match($chunk, '(?s)<div class="price">\s*([^<]+)\s*</div>')
            $oMatch = [regex]::Match($chunk, '(?s)<div class="price-old">\s*([^<]+)\s*</div>')
            $price = if ($pMatch.Success) { Parse-Money $pMatch.Groups[1].Value } else { 0 }
            $orig = if ($oMatch.Success) { Parse-Money $oMatch.Groups[1].Value } else { 0 }
            if ($orig -lt $price) { $orig = $price }

            if ($price -gt 0) {
                [void]$vtRows.Add([pscustomobject]@{
                    r = "Viettel Store"; b = $brand; n = $name; u = "https://viettelstore.vn" + $href
                    p = $price; o = $orig; k = $KM_NAME
                })
                $pageAdded++
            }
        }
        if ($pageAdded -lt 50) { break }
        Start-Sleep -Milliseconds 200
    } catch {
        Write-Host "  Viettel page $page dung lai: $_"
        break
    }
}
Write-Host "  Viettel Store hoan tat: $($vtRows.Count) may"

# --- TONG HOP TAT CA CAC SAN ---
$allRows = New-Object System.Collections.ArrayList
foreach ($r in $tgddRows) { [void]$allRows.Add($r) }
foreach ($r in $cpsRows)  { [void]$allRows.Add($r) }
foreach ($r in $fptRows)  { [void]$allRows.Add($r) }
foreach ($r in $vtRows)   { [void]$allRows.Add($r) }

Write-Host "Tong so san pham toan thi truong: $($allRows.Count) may"
$report = [pscustomobject]@{
    $TGDD_NAME = $tgddRows.Count
    "CellphoneS" = $cpsRows.Count
    "FPT Shop" = $fptRows.Count
    "Viettel Store" = $vtRows.Count
}

$now = Get-Date
$today = $now.ToString("yyyy-MM-dd")
$label = $now.ToString("dd-MMM", [Globalization.CultureInfo]::InvariantCulture)
$at = $now.ToString("HH:mm")

# --- SO SANH GIA GOC TANG (ALERTS & RISES) ---
$oldPrices = @{}
if (Test-Path $LAST_JSON) {
    try {
        $lastObj = Get-Content $LAST_JSON -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($lastObj.prices) {
            foreach ($prop in $lastObj.prices.PSObject.Properties) {
                $oldPrices[$prop.Name] = [int64]$prop.Value
            }
        }
    } catch {}
}

$ups = New-Object System.Collections.ArrayList
$newPrices = [ordered]@{}
foreach ($r in $allRows) {
    $key = "$($r.r)|$($r.u)"
    $newPrices[$key] = [int64]$r.o
    if ($oldPrices.ContainsKey($key)) {
        $before = [int64]$oldPrices[$key]
        if ($r.o -gt $before) {
            [void]$ups.Add([pscustomobject]@{
                r = $r.r; b = $r.b; n = $r.n; old = $before; new = [int64]$r.o
            })
        }
    }
}

# Luu data/market_last.json
$lastOut = [pscustomobject]@{
    day = $today
    at = $at
    prices = $newPrices
}
$lastJsonStr = $lastOut | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($LAST_JSON, $lastJsonStr, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Phat hien tang gia goc: $($ups.Count) may"

# --- CAP NHAT DATA/ALERTS.JS ---
$alerts = New-Object System.Collections.ArrayList
if (Test-Path $ALERTS_JS) {
    try {
        $aTxt = [System.IO.File]::ReadAllText($ALERTS_JS, [System.Text.Encoding]::UTF8)
        $idx = $aTxt.IndexOf('[')
        $last = $aTxt.LastIndexOf(']')
        if ($idx -ge 0 -and $last -gt $idx) {
            $aArr = $aTxt.Substring($idx, $last - $idx + 1) | ConvertFrom-Json
            foreach ($e in $aArr) {
                # Bo qua scan cua cung nguon & cung ngay de khong bi trung
                if (!($e.day -eq $today -and ($e.source -eq "market" -or $e.source -eq "tgdd-86"))) {
                    [void]$alerts.Add($e)
                }
            }
        }
    } catch {}
}
# Them entry tgdd-86 va market cho hom nay
[void]$alerts.Add([pscustomobject]@{
    source = "tgdd-86"
    day = $today
    at = $at
    items = @()
})
[void]$alerts.Add([pscustomobject]@{
    source = "market"
    day = $today
    at = $at
    items = $ups
})
# Giu toi da 120 dot
if ($alerts.Count -gt 120) {
    $alerts = New-Object System.Collections.ArrayList (,$alerts[($alerts.Count - 120)..($alerts.Count - 1)])
}
$alertsJs = "/* T\u1EF1 sinh b\u1EDFi b\u1ED9 qu\u00E9t, \u0111\u1EEBng s\u1EEDa tay. C\u00E1c l\u1EA7n gi\u00E1 \u0111en t\u0103ng theo t\u1EEBng ng\u00E0y qu\u00E9t. */`n"
$alertsJs = [regex]::Unescape($alertsJs) + "window.ALERTS = " + ($alerts | ConvertTo-Json -Depth 6 -Compress) + ";`n"
[System.IO.File]::WriteAllText($ALERTS_JS, $alertsJs, (New-Object System.Text.UTF8Encoding $false))

# --- CAP NHAT DATA/MARKET.JS ---
$market = [pscustomobject]@{ scans = @() }
if (Test-Path $MARKET_JS) {
    try {
        $mTxt = [System.IO.File]::ReadAllText($MARKET_JS, [System.Text.Encoding]::UTF8)
        $idx = $mTxt.IndexOf('{')
        $last = $mTxt.LastIndexOf('}')
        if ($idx -ge 0 -and $last -gt $idx) {
            $market = $mTxt.Substring($idx, $last - $idx + 1) | ConvertFrom-Json
        }
    } catch {}
}

$newScans = New-Object System.Collections.ArrayList
if ($market.scans) {
    foreach ($s in $market.scans) {
        if ($s.date -ne $label) {
            [void]$newScans.Add($s)
        }
    }
}

$curScan = [pscustomobject]@{
    date = $label
    at = $at
    report = $report
    rows = $allRows
}
[void]$newScans.Add($curScan)

# Giu toi da 20 scans gan nhat
if ($newScans.Count -gt 20) {
    $newScans = New-Object System.Collections.ArrayList (,$newScans[($newScans.Count - 20)..($newScans.Count - 1)])
}

$marketOut = [pscustomobject]@{ scans = $newScans }
$marketJs = "/* T\u1EF1 \u0111\u1ED9ng t\u1ED5ng h\u1EE3p 4 chu\u1ED7i b\u00E1n l\u1EBB: TGDD, CellphoneS, Viettel Store, FPT Shop */`n"
$marketJs = [regex]::Unescape($marketJs) + "window.MARKET = " + ($marketOut | ConvertTo-Json -Depth 6 -Compress) + ";`n"
[System.IO.File]::WriteAllText($MARKET_JS, $marketJs, (New-Object System.Text.UTF8Encoding $false))

# Cap nhat timestamp cho fpt.js dong bo
if (Test-Path $FPT_JS) {
    $fptTxt = [System.IO.File]::ReadAllText($FPT_JS, [System.Text.Encoding]::UTF8)
    $fptNew = [regex]::Replace($fptTxt, '"date":"[^"]+"', "`"date`":`"$label`"")
    $fptNew = [regex]::Replace($fptNew, '"at":"[^"]+"', "`"at`":`"$at`"")
    [System.IO.File]::WriteAllText($FPT_JS, $fptNew, (New-Object System.Text.UTF8Encoding $false))
}

Write-Host "=========================================="
Write-Host "DA DONG BO THANH CONG TOAN BO CAC TAB CHO NGAY $label LUC $at!"
Write-Host "  - TGDD: $($tgddRows.Count) may"
Write-Host "  - CellphoneS: $($cpsRows.Count) may"
Write-Host "  - FPT Shop: $($fptRows.Count) may"
Write-Host "  - Viettel Store: $($vtRows.Count) may"
Write-Host "  - Tong cong: $($allRows.Count) may"
Write-Host "=========================================="
