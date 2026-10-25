$ErrorActionPreference = "Stop"

# 1. Update scraper/products.csv with new models
$csvPath = (Resolve-Path "scraper/products.csv").Path
$csvLines = [System.IO.File]::ReadAllLines($csvPath, [System.Text.Encoding]::UTF8)
$csvMap = [System.Collections.Generic.Dictionary[string, string]]::new()
foreach ($line in $csvLines[1..($csvLines.Length - 1)]) {
    if (!$line.Trim()) { continue }
    $parts = $line.Split(",")
    $m = $parts[0].Trim()
    $u = $parts[1].Trim()
    $csvMap[$m] = $u
}

$newModelsCsv = @(
    @{ m = "Galaxy A26 5G 8+256GB"; u = "https://www.thegioididong.com/dtdd/samsung-galaxy-a26" },
    @{ m = "Redmi Note 17 Pro Max 8GB/256GB"; u = "https://www.thegioididong.com/dtdd/xiaomi-redmi-note-17-pro-max-5g-8gb-256gb" },
    @{ m = "Note 80 4GB/64GB"; u = "https://www.thegioididong.com/dtdd/realme-note-80-4gb-64gb" },
    @{ m = "Galaxy A08 4+128GB"; u = "https://www.thegioididong.com/dtdd/samsung-galaxy-a08-4gb-128gb" }
)

foreach ($nm in $newModelsCsv) {
    if (!$csvMap.ContainsKey($nm.m)) {
        $csvMap[$nm.m] = $nm.u
    }
}

$newCsvContent = "model,url`n" + (($csvMap.Keys | ForEach-Object { "$_,$($csvMap[$_])" }) -join "`n")
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($csvPath, $newCsvContent, $utf8NoBom)
Write-Host "Updated scraper/products.csv with $($csvMap.Count) models."

# 2. Update data/links.js
$linksPath = (Resolve-Path "data/links.js").Path
$linksRaw = [System.IO.File]::ReadAllText($linksPath, [System.Text.Encoding]::UTF8)
$idx = $linksRaw.IndexOf("{")
$lastIdx = $linksRaw.LastIndexOf("}")
$linksObj = ConvertFrom-Json $linksRaw.Substring($idx, $lastIdx - $idx + 1)

foreach ($nm in $newModelsCsv) {
    $linksObj | Add-Member -NotePropertyName $nm.m -NotePropertyValue $nm.u -Force
}
$newLinksJson = ConvertTo-Json $linksObj -Compress
$linksJs = "/* Tự sinh bởi scraper/scan_tgdd.py, đừng sửa tay. */`nwindow.LINKS = $newLinksJson;"
[System.IO.File]::WriteAllText($linksPath, $linksJs, $utf8NoBom)
Write-Host "Updated data/links.js."

# 3. Read PMH 23-Oct values from tracking sheet
$pmh23Oct = @{
    "iPhone 17 Pro Max 512GB" = 3000000
    "iPhone 18 Pro Max 256GB" = 0
    "iPhone 18 Pro 256GB" = 0
    "iPhone 17 Pro Max 256GB" = 3000000
    "iPhone 17 Pro 256GB" = 3000000
    "iPhone Air 256GB" = 12000000
    "iPhone 17 256GB" = 2000000
    "iPhone 16 128GB" = 0
    "iPhone 15 128GB" = 0
    "iPhone Duo 256GB" = 0

    "Find X9 Ultra 12GB/512GB" = 4000000
    "Find X9s 12GB/512GB" = 2700000
    "Reno16 Pro 5G 12GB/256GB" = 2600000
    "Find X9s 12GB/256GB" = 0
    "Reno16 5G 8GB/256GB" = 0
    "Reno16F 5G 8GB/256GB" = 800000
    "Reno16F 5G 8GB/128GB" = 1500000
    "A7 Pro 5G 6GB/256GB" = 1500000
    "A7 Pro 5G 8GB/128GB" = 1350000
    "A6 8GB/256GB" = 500000
    "A6 8GB/128GB" = 300000
    "A6 Pro 5G 8GB/256GB" = 0
    "A6 6GB/128GB" = 1500000
    "A6 Pro 8GB/256GB" = 0
    "A6x 6GB/256GB" = 200000
    "A6x 4GB/128GB" = 710000
    "A6c 4GB/128GB" = 0
    "A6x 4GB/64GB" = 0
    "A6c 4GB/64GB" = 0

    "S26 Ultra 5G 12GB/256GB" = 0
    "S26+ 5G 12GB/256GB" = 0
    "S25 Ultra 5G 12GB/256GB" = 4890000
    "S26 FE 5G 8GB/256GB" = 2000000
    "S25 FE 5G 8GB/256GB" = 0
    "A57 5G 12GB/256GB" = 2500000
    "A57 5G 8GB/256GB" = 2600000
    "A37 8GB/256GB" = 3100000
    "A37 5G 6GB/128GB" = 1600000
    "A27 8GB/128GB" = 1500000
    "A27 6GB/128GB" = 900000
    "A17 5G 8GB/128GB" = 500000
    "Galaxy A26 5G 8+256GB" = 850000
    "A17 5G 8GB/256GB" = 500000
    "A17 8GB/256GB" = 200000
    "Galaxy A18 4G/128GB" = 0
    "Galaxy A18 4GB/128GB" = 0
    "Galaxy A18 6GB/128GB" = 0
    "Galaxy A18 8GB/128GB" = 0
    "A17 8GB/128GB" = 200000
    "A17 4GB/128GB" = 900000
    "Galaxy A08 4+128GB" = 0
    "A08 4GB/64GB" = 0
    "A07 6GB/128GB" = 200000
    "Galaxy A07s 4GB/64GB" = 300000
    "A07 4GB/64GB" = 200000
    "A07 5G 4GB/128GB" = 1000000

    "Xiaomi 17 Ultra 5G 16GB/512GB" = 9300000
    "Xiaomi 17 5G 12GB/256GB" = 7500000
    "17T Pro 5G 12GB/256GB" = 4000000
    "17T 5G 12GB/512GB" = 3200000
    "17T 5G 12GB/256GB" = 3900000
    "Redmi Note 17 Pro Max 8GB/256GB" = 1800000
    "Redmi Note 17 Pro 5G 12GB/256GB" = 1400000
    "Redmi Note 17 Pro 5G 8GB/256GB" = 1300000
    "Redmi Note 17 Pro 5G 6GB/256GB" = 1300000
    "Redmi Note 17 5G 8GB/256GB" = 500000
    "Redmi Note 17 5G 6GB/256GB" = 500000
    "Redmi Note 17 6GB/256GB" = 500000
    "Redmi Note 17 6GB/128GB" = 500000
    "Redmi 17 4G 6GB/256GB" = 700000
    "Redmi Note 15 8GB/256GB" = 1700000
    "Redmi 17 4G 4GB/256GB" = 1200000
    "Redmi 17 5G 4GB/128GB" = 200000
    "Redmi 17 4G 4GB/128GB" = 600000
    "Redmi 15 5G 4GB/128GB" = 1000000
    "Redmi A7 Pro 4/128G" = 500000
    "Redmi 15 6GB/128GB" = $null
    "Redmi A7 Pro 4/64G" = 300000

    "X300 Ultra 16GB/512GB" = 12000000
    "V70 5G 8GB/256GB" = 1500000
    "V80 Lite 5G 6GB/256GB" = 200000
    "V70 FE 5G 8GB/256GB" = 0
    "V80 Lite 5G 6GB/128GB" = 700000
    "V60 Lite 5G 8GB/256GB" = 0
    "Y31d 8GB/128GB" = 1000000
    "Y31d 6GB/128GB" = 900000
    "Y39 5G 8GB/128GB" = 0
    "Y11d 6GB/128GB" = 0
    "Y11d 4GB/128GB" = 300000
    "Y05 4GB/128GB" = 400000
    "Y05 4GB/64GB" = 300000

    "16 Pro 5G 12GB/256GB" = 400000
    "16 5G 12GB/256GB" = 700000
    "16 5G 8GB/256GB" = 400000
    "16T 5G 8GB/256GB" = 200000
    "16T 5G 8GB/128GB" = 400000
    "C100 8GB/256GB" = 950000
    "C100 4G 8GB/128GB" = 850000
    "C85 5G 8GB/256GB" = 200000
    "C100 4G 6GB/128GB" = 850000
    "C85 Pro 8GB/256GB" = 200000
    "C100x 6GB/128GB" = 800000
    "C100x 4GB/128GB" = 700000
    "C100i 4G 4GB/128GB" = 100000
    "C85 8GB/128GB" = 200000
    "C100i 4GB/64GB" = 200000
    "Note 80 4GB/64GB" = 500000
}

# 4. Update data/data.js (BASE.rows and MASTER_ORDER)
$dataPath = (Resolve-Path "data/data.js").Path
$dataRaw = [System.IO.File]::ReadAllText($dataPath, [System.Text.Encoding]::UTF8)

$baseMatch = [regex]::Match($dataRaw, 'window\.BASE\s*=\s*(\{.*?\});\s*window\.MASTER_ORDER', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$baseObj = ConvertFrom-Json $baseMatch.Groups[1].Value

# Ensure new rows in BASE.rows
$existingModels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $baseObj.rows) {
    $existingModels.Add($r.model) | Out-Null
}

$rowsToAdd = @(
    [PSCustomObject]@{ brand = "Samsung"; model = "Galaxy A26 5G 8+256GB"; rrp = 8390000; channel = "TGDD"; segment = "7-10M"; status = "active"; pmh = @($null,$null,$null,$null,$null,$null,$null,$null,$null); is_new = $true },
    [PSCustomObject]@{ brand = "Samsung"; model = "Galaxy A08 4+128GB"; rrp = 5590000; channel = "TGDD"; segment = "5-7M"; status = "active"; pmh = @($null,$null,$null,$null,$null,$null,$null,$null,$null); is_new = $true },
    [PSCustomObject]@{ brand = "Xiaomi"; model = "Redmi Note 17 Pro Max 8GB/256GB"; rrp = 15990000; channel = "TGDD"; segment = "15-20M"; status = "active"; pmh = @($null,$null,$null,$null,$null,$null,$null,$null,$null); is_new = $true },
    [PSCustomObject]@{ brand = "Realme"; model = "Note 80 4GB/64GB"; rrp = 4690000; channel = "TGDD"; segment = "<5M"; status = "active"; pmh = @($null,$null,$null,$null,$null,$null,$null,$null,$null); is_new = $true }
)

$rowsList = [System.Collections.Generic.List[object]]::new($baseObj.rows)
foreach ($rta in $rowsToAdd) {
    if (!$existingModels.Contains($rta.model)) {
        $rowsList.Add($rta)
        $existingModels.Add($rta.model) | Out-Null
    }
}
$baseObj.rows = $rowsList.ToArray()

# Build comprehensive MASTER_ORDER in exact brand order
$masterOrderList = @(
    # Apple (9)
    "iPhone 17 Pro Max 512GB","iPhone 18 Pro Max 256GB","iPhone 18 Pro 256GB","iPhone 17 Pro Max 256GB","iPhone 17 Pro 256GB","iPhone Air 256GB","iPhone 17 256GB","iPhone 16 128GB","iPhone 15 128GB","iPhone Duo 256GB",
    # OPPO (19)
    "Find X9 Ultra 12GB/512GB","Find X9s 12GB/512GB","Reno16 Pro 5G 12GB/256GB","Find X9s 12GB/256GB","Reno16 5G 8GB/256GB","Reno16F 5G 8GB/256GB","Reno16F 5G 8GB/128GB","A7 Pro 5G 6GB/256GB","A7 Pro 5G 8GB/128GB","A6 8GB/256GB","A6 8GB/128GB","A6 Pro 5G 8GB/256GB","A6 6GB/128GB","A6 Pro 8GB/256GB","A6x 6GB/256GB","A6x 4GB/128GB","A6c 4GB/128GB","A6x 4GB/64GB","A6c 4GB/64GB",
    # Samsung (24)
    "S26 Ultra 5G 12GB/256GB","S26+ 5G 12GB/256GB","S25 Ultra 5G 12GB/256GB","S26 FE 5G 8GB/256GB","S25 FE 5G 8GB/256GB","A57 5G 12GB/256GB","A57 5G 8GB/256GB","A37 8GB/256GB","A37 5G 6GB/128GB","A27 8GB/128GB","A27 6GB/128GB","A17 5G 8GB/128GB","Galaxy A26 5G 8+256GB","A17 5G 8GB/256GB","A17 8GB/256GB","Galaxy A18 8GB/128GB","Galaxy A18 6GB/128GB","Galaxy A18 4GB/128GB","Galaxy A18 4G/128GB","A17 8GB/128GB","A07 5G 4GB/128GB","A17 4GB/128GB","Galaxy A08 4+128GB","A08 4GB/64GB","A07 6GB/128GB","Galaxy A07s 4GB/64GB","A07 4GB/64GB",
    # Xiaomi (19)
    "Xiaomi 17 Ultra 5G 16GB/512GB","Xiaomi 17 5G 12GB/256GB","17T Pro 5G 12GB/256GB","17T 5G 12GB/512GB","17T 5G 12GB/256GB","Redmi Note 17 Pro Max 8GB/256GB","Redmi Note 17 Pro 5G 12GB/256GB","Redmi Note 17 Pro 5G 8GB/256GB","Redmi Note 17 Pro 5G 6GB/256GB","Redmi Note 17 5G 8GB/256GB","Redmi Note 17 5G 6GB/256GB","Redmi Note 17 6GB/256GB","Redmi Note 17 6GB/128GB","Redmi 17 4G 6GB/256GB","Redmi Note 15 8GB/256GB","Redmi 17 4G 4GB/256GB","Redmi 17 5G 4GB/128GB","Redmi 17 4G 4GB/128GB","Redmi 15 5G 4GB/128GB","Redmi A7 Pro 4/128G","Redmi 15 6GB/128GB","Redmi A7 Pro 4/64G",
    # Vivo (11)
    "X300 Ultra 16GB/512GB","V70 5G 8GB/256GB","V80 Lite 5G 6GB/256GB","V70 FE 5G 8GB/256GB","V80 Lite 5G 6GB/128GB","V60 Lite 5G 8GB/256GB","Y31d 8GB/128GB","Y31d 6GB/128GB","Y39 5G 8GB/128GB","Y11d 6GB/128GB","Y11d 4GB/128GB","Y05 4GB/128GB","Y05 4GB/64GB",
    # Realme (15)
    "16 Pro 5G 12GB/256GB","16 5G 12GB/256GB","16 5G 8GB/256GB","16T 5G 8GB/256GB","16T 5G 8GB/128GB","C100 8GB/256GB","C100 4G 8GB/128GB","C85 5G 8GB/256GB","C100 4G 6GB/128GB","C85 Pro 8GB/256GB","C100x 6GB/128GB","C100x 4GB/128GB","C100i 4G 4GB/128GB","C85 8GB/128GB","C100i 4GB/64GB","Note 80 4GB/64GB"
)

# Filter MASTER_ORDER so only models that actually exist in BASE.rows are included
$validMasterOrder = $masterOrderList | Where-Object { $existingModels.Contains($_) } | Select-Object -Unique

# Reconstruct data/data.js
$newBaseJson = ConvertTo-Json $baseObj -Depth 10 -Compress
$newMasterJson = ConvertTo-Json $validMasterOrder -Compress

$restOfDataJs = $dataRaw.Substring($dataRaw.IndexOf("window.RRP_NOTES ="))

$newDataJs = "/* Dữ liệu gốc của trang. Sửa file này để cập nhật số liệu, không cần đụng index.html. */`nwindow.BASE = $newBaseJson;`nwindow.MASTER_ORDER = $newMasterJson;`n`n$restOfDataJs"
[System.IO.File]::WriteAllText($dataPath, $newDataJs, $utf8NoBom)
Write-Host "Updated data/data.js with $($baseObj.rows.Count) rows and $($validMasterOrder.Count) MASTER_ORDER items."

# 5. Update data/scans.js and data/latest.js
$scansPath = (Resolve-Path "data/scans.js").Path
$scansRaw = [System.IO.File]::ReadAllText($scansPath, [System.Text.Encoding]::UTF8)
$sIdx = $scansRaw.IndexOf("[")
$sLastIdx = $scansRaw.LastIndexOf("]")
$scansList = ConvertFrom-Json $scansRaw.Substring($sIdx, $sLastIdx - $sIdx + 1)

$scan23 = $scansList | Where-Object { $_.date -eq "23-Oct" }
if (!$scan23) {
    Write-Host "Creating new 23-Oct scan entry in scans.js..."
    $scan23 = [PSCustomObject]@{
        date = "23-Oct"
        rows = @()
    }
    $scansList = @($scansList) + @($scan23)
}

# Update or build 23-Oct rows
$rowMap = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($r in $scan23.rows) {
    $rowMap[$r.model] = $r
}

foreach ($m in $pmh23Oct.Keys) {
    $pmhVal = $pmh23Oct[$m]
    # Find rrp from BASE.rows
    $baseRow = $baseObj.rows | Where-Object { $_.model -eq $m }
    $rrp = if ($baseRow) { $baseRow.rrp } else { 0 }
    
    $existing = if ($rowMap.ContainsKey($m)) { $rowMap[$m] } else { $null }
    if (!$existing) {
        $existing = [PSCustomObject]@{
            model = $m
            rrp = $rrp
            red = if ($pmhVal -ne $null) { $rrp - $pmhVal } else { $rrp }
            pmh = $pmhVal
            status = if ($pmhVal -ne $null) { "active" } else { "no_price" }
            online = if ($pmhVal -ne $null) { $pmhVal } else { 0 }
            total_online = if ($pmhVal -ne $null) { $pmhVal } else { 0 }
            choice = 0
            kind = "moi"
            rule = "den_tru_do"
        }
        $rowMap[$m] = $existing
    } else {
        $existing.rrp = $rrp
        $existing.pmh = $pmhVal
        if ($pmhVal -ne $null) {
            $existing.status = "active"
            $existing.red = $rrp - $pmhVal
            $existing.online = $pmhVal
            $existing.total_online = $pmhVal
        }
    }
}

# Specific overrides for A7 Pro 5G models
if ($rowMap.ContainsKey("A7 Pro 5G 6GB/256GB")) {
    $r = $rowMap["A7 Pro 5G 6GB/256GB"]
    $r.rrp = 14490000
    $r.red = 12990000
    $r.pmh = 1500000
    $r.status = "active"
    $r.online = 1500000
    $r.total_online = 1500000
    $r.choice = 1500000
    $r.kind = "moi"
    $r.rule = "chon1"
}
if ($rowMap.ContainsKey("A7 Pro 5G 8GB/128GB")) {
    $r = $rowMap["A7 Pro 5G 8GB/128GB"]
    $r.rrp = 13490000
    $r.red = 12140000
    $r.pmh = 1350000
    $r.status = "active"
    $r.online = 1350000
    $r.total_online = 1350000
    $r.choice = 0
    $r.kind = "brand_tab"
    $r.rule = "den_tru_do"
}

# Order 23-Oct rows according to validMasterOrder
$orderedRows23 = [System.Collections.Generic.List[object]]::new()
foreach ($m in $validMasterOrder) {
    if ($rowMap.ContainsKey($m)) {
        $orderedRows23.Add($rowMap[$m])
    }
}
# Add any leftovers
foreach ($k in $rowMap.Keys) {
    if (!$validMasterOrder.Contains($k)) {
        $orderedRows23.Add($rowMap[$k])
    }
}

$scan23.rows = $orderedRows23.ToArray()

# Write back data/scans.js
$newScansJson = ConvertTo-Json $scansList -Depth 10 -Compress
$scansJs = "/* Tự sinh bởi scraper/scan_tgdd.py, đừng sửa tay. */`nwindow.SCANS = $newScansJson;"
[System.IO.File]::WriteAllText($scansPath, $scansJs, $utf8NoBom)
Write-Host "Updated data/scans.js with 23-Oct scan."

# 6. Update data/latest.js
$latestPath = (Resolve-Path "data/latest.js").Path
$latestObj = [PSCustomObject]@{
    date = "23-Oct"
    rows = $orderedRows23.ToArray()
}
$newLatestJson = ConvertTo-Json $latestObj -Depth 10 -Compress
$latestJs = "/* Tự sinh bởi scraper/scan_tgdd.py, đừng sửa tay. */`nwindow.LATEST = $newLatestJson;"
[System.IO.File]::WriteAllText($latestPath, $latestJs, $utf8NoBom)
Write-Host "Updated data/latest.js with 23-Oct."
