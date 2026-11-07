# ==============================================================================
# HỆ THỐNG KIỂM TRA TOÀN VẸN VÀ RÀNG BUỘC (CONSTRAINTS VERIFICATION SUITE)
# Tuân thủ phương pháp Test-Driven & Constraint-Driven Development (Addy Osmani)
# ==============================================================================

$ErrorActionPreference = "Stop"
$TotalChecks = 0
$PassedChecks = 0
$FailedChecks = 0

function Assert-Check {
    param(
        [string]$Name,
        [scriptblock]$Condition,
        [string]$FailureMessage
    )
    $script:TotalChecks++
    Write-Host -NoNewline "[$script:TotalChecks] Checking: $Name ... "
    try {
        $result = & $Condition
        if ($result -eq $true) {
            Write-Host "PASS" -ForegroundColor Green
            $script:PassedChecks++
        } else {
            Write-Host "FAIL" -ForegroundColor Red
            Write-Host "    -> ERROR: $FailureMessage" -ForegroundColor Red
            $script:FailedChecks++
        }
    } catch {
        Write-Host "ERROR" -ForegroundColor Red
        Write-Host "    -> EXCEPTION: $($_.Exception.Message)" -ForegroundColor Red
        $script:FailedChecks++
    }
}

# Ghi nhan mot that bai cung (dung cho truong hop mot nhom test khong the chay duoc:
# truoc day Chrome khong co thi Nhom 4 bi bo qua am tham va suite van bao "PASS").
function Assert-Hard-Fail {
    param([string]$Name, [string]$FailureMessage)
    $script:TotalChecks++
    Write-Host "[$script:TotalChecks] Checking: $Name ... FAIL" -ForegroundColor Red
    Write-Host "    -> ERROR: $FailureMessage" -ForegroundColor Red
    $script:FailedChecks++
}

# Moi nguong so lieu doc tu MOT nguon duy nhat.
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$GateCfg = Get-Content (Join-Path $PSScriptRoot "gate-config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$TodayVN = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
    [datetime]::UtcNow, 'UTC', 'SE Asia Standard Time')

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   BAT DAU KIEM TRA TOAN BO HE THONG THEO AGENT-SKILLS GATES     " -ForegroundColor Cyan
Write-Host "   Master List: $($GateCfg.masterSkuCount) SKU | Hom nay (VN): $($TodayVN.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# NHÓM 0: DỮ LIỆU CỦA ĐỢT QUÉT HÔM NAY (DYNAMIC - KHÔNG NEO VÀO NGÀY CỨNG)
#
# Toàn bộ các nhóm phía dưới là regression guard cho những lỗi đã xảy ra trong
# tháng 10 - chúng neo vào ngày và giá cố định nên KHÔNG soi vào dữ liệu mới.
# Nhóm 0 này mới là thứ kiểm dữ liệu của ngày hôm nay.
# ------------------------------------------------------------------------------
Write-Host "`n--- [Nhom 0] Kiem dinh du lieu dot quet HOM NAY ---" -ForegroundColor Yellow

$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) {
    Assert-Hard-Fail "Circuit Breaker (tests/verify_scan.js) phai chay duoc" `
        "Khong tim thay Node.js tren PATH - khong the kiem dinh du lieu dot quet. Cai Node.js roi chay lai."
} else {
    # $ErrorActionPreference='Stop' + `2>&1` tren lenh native se bien stderr thanh
    # NativeCommandError va lam abort ca suite. Ha xuong 'Continue' quanh loi goi nay.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $cbOutput = & node "tests/verify_scan.js" 2>&1 | ForEach-Object { "$_" }
    $cbExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    Assert-Check "Circuit Breaker: du lieu dot quet hom nay phai thoa man toan bo Domain Invariants" {
        $cbExit -eq 0
    } ("Circuit breaker bao loi (chay 'node tests/verify_scan.js' de xem day du):`n" +
       (($cbOutput | Where-Object { $_ -match '\d+\.\s' -or $_ -match 'VI PHAM' }) -join "`n"))
}

Assert-Check "data/scans/ phai co dot quet cua HOM NAY ($($TodayVN.ToString('yyyy-MM-dd')))" {
    Test-Path ("data/scans/scan_{0}.json" -f $TodayVN.ToString('yyyy-MM-dd'))
} "Khong co data/scans/scan_$($TodayVN.ToString('yyyy-MM-dd')).json - buoc quet hom nay da that bai hoac chua chay"

Assert-Check "data/latest.js phai tro dung vao dot quet hom nay" {
    $ltRaw = (Get-Content "data/latest.js" -Raw -Encoding UTF8) -replace '^\s*/\*.*?\*/\s*', '' -replace '^\s*window\.LATEST\s*=\s*', ''
    $ltObj = $ltRaw.TrimEnd(" ;`r`n") | ConvertFrom-Json
    $ltObj.date -eq $TodayVN.ToString('dd-MMM', [cultureinfo]::GetCultureInfo('en-US'))
} "data/latest.js khong phai dot quet hom nay ($($TodayVN.ToString('dd-MMM', [cultureinfo]::GetCultureInfo('en-US'))))"

# write_scans_js() co chu y chi giu `scansJsRetention` dot gan nhat (scans[-30:]),
# nen dot cu hon bi rot ra KHONG phai loi. Chi thung TRONG cua so giu lai moi la loi.
Assert-Check "Trong cua so $($GateCfg.scansJsRetention) dot gan nhat, data/scans.js khong duoc bo sot dot nao" {
    $scansRaw = (Get-Content "data/scans.js" -Raw -Encoding UTF8) -replace '^\s*/\*.*?\*/\s*', '' -replace '^\s*window\.SCANS\s*=\s*', ''
    $scansObj = $scansRaw.TrimEnd(" ;`r`n") | ConvertFrom-Json
    $known = @{}; foreach ($s in $scansObj) { $known[$s.date] = $true }
    $retained = Get-ChildItem "data/scans" -Filter "scan_*.json" | Sort-Object Name | Select-Object -Last $GateCfg.scansJsRetention
    $gap = @()
    foreach ($f in $retained) {
        $d = ([datetime]($f.BaseName -replace 'scan_', '')).ToString('dd-MMM', [cultureinfo]::GetCultureInfo('en-US'))
        if (-not $known.ContainsKey($d)) { $gap += $f.Name }
    }
    ($gap.Count -eq 0) -and ($scansObj.Count -eq $retained.Count)
} "data/scans.js thung dot quet trong cua so $($GateCfg.scansJsRetention) dot gan nhat (vi pham CONSTRAINTS 2.4)"

# ------------------------------------------------------------------------------
# NHÓM 1: QUY TẮC BẤT BIẾN SCRAPER (SCAN_TGDD.PY)
# ------------------------------------------------------------------------------
Write-Host "`n--- [Nhom 1] Kiem tra quy tac Scraper (scraper/scan_tgdd.py) ---" -ForegroundColor Yellow

$scanScript = "scraper/scan_tgdd.py"
Assert-Check "File scraper/scan_tgdd.py phai ton tai" {
    Test-Path $scanScript
} "Khong tim thay file $scanScript"

if (Test-Path $scanScript) {
    $scanContent = Get-Content $scanScript -Raw -Encoding UTF8

    Assert-Check "Quy tac Flash Sale: 'Uu dai ONLINE' va 'Ket thuc sau' phai nam trong FLASH_KEYWORDS_RE" {
        $scanContent -match 'FLASH_KEYWORDS_RE' -and $scanContent -match 'ONLINE' -and $scanContent -match 'sau'
    } "FLASH_KEYWORDS_RE thieu tu khoa Flash Sale"

    Assert-Check "Quy tac Flash Sale: Phai co BANNER CAM (ORANGE_BANNER_RE / has_banner_cam)" {
        $scanContent -match 'ORANGE_BANNER_RE' -and $scanContent -match 'has_banner_cam'
    } "Khong tim thay bien phap xac minh BANNER CAM trong scan_tgdd.py"

    Assert-Check "Quy tac Flash Sale: banner = has_banner_cam and has_flash_kw" {
        $scanContent -match 'banner\s*=\s*bool\(has_banner_cam\s+and\s+has_flash_kw\)'
    } "Dieu kien banner flash sale phai ket hop ca Banner Cam va Tu khoa Flash Sale"

    Assert-Check "Quy tac PMH khi co Banner Cam: PMH = choice (flash_chon1)" {
        $scanContent -match 'pmh,\s*rule\s*=\s*choice,\s*"flash_chon1"'
    } "Thieu quy tac PMH = choice khi co banner cam"

    Assert-Check "Quy tac Scraper: Ham extract_choice phai tach rieng va xu ly chon 1 trong, lstGift" {
        $scanContent -match 'def extract_choice\(' -and $scanContent -match 'lstGift'
    } "Thieu ham extract_choice xu ly tong the cac dang choice"

    Assert-Check "Quy tac Scraper: write_scans_js khong duoc bo sot cac dot quet giua tuan" {
        $scanContent -notmatch 'if\s+day\.weekday\(\)\s+not\s+in\s+alerts\.KEEP_WEEKDAYS'
    } "write_scans_js khong duoc bo sot dot quet vi KEEP_WEEKDAYS"

    Assert-Check "Quy tac Alerts: load_base_rrp_map phai nap ca baseline data.js va scans.js" {
        $alertsText = Get-Content "scraper/alerts.py" -Raw -Encoding UTF8
        $alertsText -match 'def load_base_rrp_map\(\):' -and $alertsText -match 'scans_file\.exists\(\)'
    } "load_base_rrp_map phai nap ca baseline data.js va scans.js de theo doi du 106+ SKU"

    Assert-Check "Quy tac Fast-Check: scan_tgdd.py phai dinh nghia ham fast_check_o3" {
        $scanContent -match 'def fast_check_o3\('
    } "scan_tgdd.py thieu ham fast_check_o3"

    Assert-Check "CONSTRAINTS.md phai quy dinh chuan tham chieu Ground Truth dtdd#o=3" {
        $cText = Get-Content "CONSTRAINTS.md" -Raw -Encoding UTF8
        ($cText -match 'dtdd#o=3') -and ($cText -match 'Ground Truth')
    } "CONSTRAINTS.md thieu muc 2.6 ve chuan tham chieu Ground Truth dtdd#o=3"
}

# ------------------------------------------------------------------------------
# NHÓM 2: TÍNH TOÀN VẸN DỮ LIỆU (DATA INTEGRITY & SYNCHRONIZATION)
# ------------------------------------------------------------------------------
Write-Host "`n--- [Nhom 2] Kiem tra dong bo du lieu (data/*.js) ---" -ForegroundColor Yellow

Assert-Check "File data/latest.js phai ton tai" { Test-Path "data/latest.js" } "Thieu data/latest.js"
Assert-Check "File data/scans.js phai ton tai" { Test-Path "data/scans.js" } "Thieu data/scans.js"
Assert-Check "File data/data.js phai ton tai" { Test-Path "data/data.js" } "Thieu data/data.js"

if ((Test-Path "data/latest.js") -and (Test-Path "data/scans.js")) {
    $latestContent = Get-Content "data/latest.js" -Raw -Encoding UTF8
    $scansContent = Get-Content "data/scans.js" -Raw -Encoding UTF8

    Assert-Check "data/latest.js phai dinh nghia window.LATEST chua rows" {
        $latestContent -match 'window\.LATEST\s*=' -and $latestContent -match '"rows"\s*:\s*\['
    } "latest.js thieu window.LATEST hoac rows"

    Assert-Check "data/scans.js phai chua lich su dot quet 19-Oct" {
        $scansContent -match '"19-Oct"'
    } "scans.js thieu ban ghi dot quet ngay 19-Oct"

    Assert-Check "products.csv phai co DUNG $($GateCfg.masterSkuCount) SKU theo Master List" {
        $csvSku = ((Get-Content "scraper/products.csv") | Where-Object { $_.Trim() }).Count - 1
        $csvSku -eq $GateCfg.masterSkuCount
    } "products.csv co $(((Get-Content 'scraper/products.csv') | Where-Object { $_.Trim() }).Count - 1) SKU, Master List quy dinh DUNG $($GateCfg.masterSkuCount) (sua tests/gate-config.json neu day la thay doi co chu y)"

    Assert-Check "scraper/products.csv phai chua model chuan 'A7 Pro 5G 6GB/256GB' va 'A7 Pro 5G 8GB/128GB'" {
        $csvText = Get-Content "scraper/products.csv" -Raw -Encoding UTF8
        ($csvText -match 'A7 Pro 5G 6GB/256GB') -and ($csvText -match 'A7 Pro 5G 8GB/128GB') -and ($csvText -notmatch 'A7 Pro 5G 8GB/256GB')
    } "products.csv khong chua 'A7 Pro 5G 6GB/256GB' hoac van con ma loi 'A7 Pro 5G 8GB/256GB'"

    Assert-Check "data/links.js phai chua link cho 'A7 Pro 5G 6GB/256GB' va 'A7 Pro 5G 8GB/128GB'" {
        $linksText = Get-Content "data/links.js" -Raw -Encoding UTF8
        ($linksText -match '"A7 Pro 5G 6GB/256GB"') -and ($linksText -match '"A7 Pro 5G 8GB/128GB"')
    } "data/links.js thieu key 'A7 Pro 5G 6GB/256GB' hoac 'A7 Pro 5G 8GB/128GB'"

    Assert-Check "data/latest.js phai co 'A7 Pro 5G 6GB/256GB' active (red 13.990.000, PMH 500.000) va 'A7 Pro 5G 8GB/128GB' active (red 11.870.000, PMH 1.620.000)" {
        $latestText = Get-Content "data/latest.js" -Raw -Encoding UTF8
        ($latestText -match '"model"\s*:\s*"A7 Pro 5G 6GB/256GB"[^}]*"red"\s*:\s*13990000' -and $latestText -match '"model"\s*:\s*"A7 Pro 5G 6GB/256GB"[^}]*"pmh"\s*:\s*500000') -and
        ($latestText -match '"model"\s*:\s*"A7 Pro 5G 8GB/128GB"[^}]*"red"\s*:\s*11870000' -and $latestText -match '"model"\s*:\s*"A7 Pro 5G 8GB/128GB"[^}]*"pmh"\s*:\s*1620000')
    } "data/latest.js thieu hoac sai so lieu A7 Pro 5G cac bien the"

    Assert-Check "data/latest.js phai co 'V80 Lite 5G 6GB/256GB' (RRP 14.990.000) va 'V80 Lite 5G 6GB/128GB' (RRP 12.990.000) active" {
        $latestText = Get-Content "data/latest.js" -Raw -Encoding UTF8
        ($latestText -match '"model"\s*:\s*"V80 Lite 5G 6GB/256GB"[^}]*"rrp"\s*:\s*14990000' -and $latestText -match '"model"\s*:\s*"V80 Lite 5G 6GB/256GB"[^}]*"status"\s*:\s*"active"') -and
        ($latestText -match '"model"\s*:\s*"V80 Lite 5G 6GB/128GB"[^}]*"rrp"\s*:\s*12990000' -and $latestText -match '"model"\s*:\s*"V80 Lite 5G 6GB/128GB"[^}]*"status"\s*:\s*"active"')
    } "data/latest.js thieu hoac sai so lieu V80 Lite 5G"

    Assert-Check "data/scans.js dot quet 26-Oct phai co 'V80 Lite 5G 6GB/256GB' va 'V80 Lite 5G 6GB/128GB' voi PMH 700.000" {
        $scansText = Get-Content "data/scans.js" -Raw -Encoding UTF8
        $raw = $scansText -replace '^\s*/\*.*?\*/\s*', '' -replace '^\s*window\.SCANS\s*=\s*', ''
        $raw = $raw.TrimEnd(" ;
")
        $scansObj = $raw | ConvertFrom-Json
        $s26Obj = $scansObj | Where-Object { $_.date -eq "26-Oct" }
        $v256 = $s26Obj.rows | Where-Object { $_.model -eq "V80 Lite 5G 6GB/256GB" }
        $v128 = $s26Obj.rows | Where-Object { $_.model -eq "V80 Lite 5G 6GB/128GB" }
        ($v256.pmh -eq 700000) -and ($v256.rrp -eq 14990000) -and ($v128.pmh -eq 700000) -and ($v128.rrp -eq 12990000)
    } "data/scans.js dot quet 26-Oct sai PMH hoac RRP cua V80 Lite"

    Assert-Check "data/latest.js phai co A08 4GB/64GB RRP 4.790.000 (khong bi nham 5.590.000)" {
        $latestText = Get-Content "data/latest.js" -Raw -Encoding UTF8
        ($latestText -match '"model"\s*:\s*"A08 4GB/64GB"[^}]*"rrp"\s*:\s*4790000') -and
        ($latestText -notmatch '"model"\s*:\s*"A08 4GB/64GB"[^}]*"rrp"\s*:\s*5590000')
    } "data/latest.js bi nham RRP A08 4GB/64GB thanh 5.590.000"

    Assert-Check "data/alerts.js va data/rises.js tuyet doi khong bao tang gia ao cho A08 4GB/64GB" {
        $alertsText = Get-Content "data/alerts.js" -Raw -Encoding UTF8
        $risesText = Get-Content "data/rises.js" -Raw -Encoding UTF8
        ($alertsText -notmatch "A08 4GB/64GB") -and ($risesText -notmatch "A08 4GB/64GB")
    } "alerts.js hoac rises.js van con chua bao tang gia ao A08 4GB/64GB"
    Assert-Check "data/alerts.js va data/rises.js tuyet doi khong bao tang gia ao cho Galaxy A18" {
        $alertsText = Get-Content "data/alerts.js" -Raw -Encoding UTF8
        $risesText = Get-Content "data/rises.js" -Raw -Encoding UTF8
        ($alertsText -notmatch "Galaxy A18 4G") -and ($risesText -notmatch "Galaxy A18 4G")
    } "alerts.js hoac rises.js van con chua bao tang gia ao Galaxy A18"

    Assert-Check "data/rises.js khong chua bat ky dong tang gia nao co Brand bi trong" {
        $risesText = Get-Content "data/rises.js" -Raw -Encoding UTF8
        $risesText -notmatch '\["T\d+",\s*"",'
    } "data/rises.js van con ton tai dong co Brand bi trong"

    Assert-Check "data/rises.js phai co du 5 model Realme C100 va C100x tang gia trong T11" {
        $risesText = Get-Content "data/rises.js" -Raw -Encoding UTF8
        ($risesText -match '"C100 8GB/256GB"') -and
        ($risesText -match '"C100 4G 8GB/128GB"') -and
        ($risesText -match '"C100 4G 6GB/128GB"') -and
        ($risesText -match '"C100x 6GB/128GB"') -and
        ($risesText -match '"C100x 4GB/128GB"')
    } "data/rises.js thieu model Realme C100 hoac C100x tang gia T11"

    Assert-Check "data/scans.js dot quet 26-Oct phai co A08 4GB/64GB voi RRP 4.790.000" {
        $scansText = Get-Content "data/scans.js" -Raw -Encoding UTF8
        $raw = $scansText -replace "^\s*/\*.*?\*/\s*", "" -replace "^\s*window\.SCANS\s*=\s*", ""
        $raw = $raw.TrimEnd(" ;`r`n")
        $scansObj = $raw | ConvertFrom-Json
        $s26Obj = $scansObj | Where-Object { $_.date -eq "26-Oct" }
        $a08 = $s26Obj.rows | Where-Object { $_.model -eq "A08 4GB/64GB" }
        $a08.rrp -eq 4790000
    } "data/scans.js 26-Oct sai RRP A08 4GB/64GB"

    Assert-Check "data/market.js quet 27-Oct phai co FPT Shop ban Galaxy A18 6GB 128GB dung 7.190.000 (khong bi 6.490.000)" {
        $mktText = Get-Content "data/market.js" -Raw -Encoding UTF8
        $raw = $mktText -replace '^\s*/\*.*?\*/\s*', '' -replace '^\s*window\.MARKET\s*=\s*', ''
        $raw = $raw.TrimEnd(" ;`r`n")
        $mktObj = $raw | ConvertFrom-Json
        $s27 = $mktObj.scans | Where-Object { $_.date -eq "27-Oct" }
        $a18Fpt = $s27.rows | Where-Object { $_.r -eq "FPT Shop" -and $_.n -like "*A18*6GB*128GB*" }
        $a18Fpt -and ($a18Fpt.p -eq 7190000)
    } "data/market.js scan 27-Oct sai gia FPT Shop cho Galaxy A18 (phai la 7.190.000)"

    Assert-Check "data/market.js quet 27-Oct phai co CellphoneS ban Samsung Galaxy A17 8GB 128GB dung 5.490.000 (khong bi 5.690.000)" {
        $mktText = Get-Content "data/market.js" -Raw -Encoding UTF8
        $raw = $mktText -replace '^\s*/\*.*?\*/\s*', '' -replace '^\s*window\.MARKET\s*=\s*', ''
        $raw = $raw.TrimEnd(" ;`r`n")
        $mktObj = $raw | ConvertFrom-Json
        $cur = $mktObj.scans[-1]
        $a17Cps = $cur.rows | Where-Object { $_.r -eq "CellphoneS" -and $_.n -like "*A17*8GB*128GB*" }
        $a17Cps -and ($a17Cps.p -eq 5490000)
    } "data/market.js scan moi nhat sai gia CellphoneS cho Galaxy A17 8GB 128GB (phai la 5.490.000)"

    Assert-Check "data/fpt.js phai co A18 6GB 128GB dung gia" {
        $fptText = Get-Content "data/fpt.js" -Raw -Encoding UTF8
        ($fptText -match '"Samsung Galaxy A18 6GB 128GB"') -and
        ($fptText -match '"p"\s*:\s*(?:6790000|7190000)')
    } "data/fpt.js chua co hoac sai gia A18"

    Assert-Check "mkMergeFpt() trong index.html phai kiem tra L.date !== scan.date tranh de du lieu cu ghi de" {
        $idxText = Get-Content "index.html" -Raw -Encoding UTF8
        $idxText -match 'L\.date\s*!==\s*scan\.date'
    } "index.html thieu kiem tra L.date !== scan.date trong mkMergeFpt"

    Assert-Check "canonKey() trong index.html tuyet doi khong co quy tac hack dong bo bien the a7pro5g" {
        $idxText = Get-Content "index.html" -Raw -Encoding UTF8
        $idxText -notmatch 'oppo_a7pro5g8gb256gb'
    } "index.html van con chua ma hack canonKey dong bo bien the a7pro5g"

    Assert-Check "Toan bo cac file trong data/scans/ khong chua model bi duplicate va khong lech quy tac flash_chon1" {
        $scanFiles = Get-ChildItem -Path "data/scans" -Filter "scan_*.json"
        $allValid = $true
        foreach ($sf in $scanFiles) {
            $raw = Get-Content $sf.FullName -Raw -Encoding UTF8
            $scanObj = $raw | ConvertFrom-Json
            $seen = @{}
            foreach ($r in $scanObj.rows) {
                if ($seen.ContainsKey($r.model)) {
                    $allValid = $false
                    break
                }
                $seen[$r.model] = $true
                if ($r.rule -eq "flash_chon1" -and $r.choice -ne $null -and $r.pmh -ne $r.choice) {
                    $allValid = $false
                    break
                }
            }
            if (-not $allValid) { break }
        }
        $allValid
    } "Phat hien loi duplicate hoac rule flash_chon1 lech choice trong data/scans/"

    Assert-Check "data/latest.js phai chua dung gia va rule cho OPPO A6 8GB/256GB (red 11.490.000, PMH 500.000, den_tru_do)" {
        $ltText = Get-Content "data/latest.js" -Raw -Encoding UTF8
        $raw = $ltText -replace '^\s*/\*.*?\*/\s*', '' -replace '^\s*window\.LATEST\s*=\s*', ''
        $raw = $raw.TrimEnd(" ;`r`n")
        $ltObj = $raw | ConvertFrom-Json
        $a6 = $ltObj.rows | Where-Object { $_.model -eq "A6 8GB/256GB" }
        $a6 -and ($a6.rrp -eq 11990000) -and ($a6.red -eq 11490000) -and ($a6.pmh -eq 500000) -and ($a6.rule -eq "den_tru_do")
    } "data/latest.js sai thong so gia / PMH cua OPPO A6 8GB/256GB"
}

# ------------------------------------------------------------------------------
# NHÓM 3: GIAO DIỆN & XUẤT EXCEL (UI & EXCEL EXPORT INTEGRITY)
# ------------------------------------------------------------------------------
Write-Host "`n--- [Nhom 3] Kiem tra chuc nang Xuat Excel & UI Files ---" -ForegroundColor Yellow

$htmlFiles = @("index.html", "promotion tgdd.html", "promotion tgdd standalone.html")

foreach ($file in $htmlFiles) {
    Assert-Check "File $file phai ton tai" { Test-Path $file } "Thieu file $file"
    if (Test-Path $file) {
        $htmlContent = Get-Content $file -Raw -Encoding UTF8

        Assert-Check "File $file phai co thu vien SheetJS hoac XLSX object" {
            $htmlContent -match 'xlsx(\.full)?\.min\.js' -or $htmlContent -match 'XLSX\.utils'
        } "$file thieu thu vien SheetJS"

        Assert-Check "File $file phai co Sheet 1: KM_Chi_Tiet_TGDD" {
            $htmlContent -match 'KM_Chi_Tiet_TGDD'
        } "$file thieu Sheet 1 trong ham xuat Excel"

        Assert-Check "File $file phai co Sheet 2: Lich_Su_Theo_Dot_Quet" {
            $htmlContent -match 'Lich_Su_Theo_Dot_Quet'
        } "$file thieu Sheet 2 trong ham xuat Excel"

        Assert-Check "File $file phai co Sheet 3: Ma_Tran_4_San" {
            $htmlContent -match 'Ma_Tran_4_San'
        } "$file thieu Sheet 3 trong ham xuat Excel"

        Assert-Check "File $file phai co nut xuat Lich Su Theo Dot Quet chuyen biet" {
            $htmlContent -match 'history-xlsx'
        } "$file thieu nut history-xlsx"

    }
}

# ------------------------------------------------------------------------------
# NHÓM 4: TEST THỰC TẾ TRÊN TRÌNH DUYỆT (E2E CHROME HEADLESS EXPORT TEST)
# ------------------------------------------------------------------------------
Write-Host "`n--- [Nhom 4] Kiem tra thuc te E2E xuat file Excel (Chrome Headless) ---" -ForegroundColor Yellow

$e2eHtml = "tests/test-excel-e2e.html"
$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromePath)) {
    $chromePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
}

# Truoc day: thieu Chrome thi ca Nhom 4 bi bo qua am tham, suite tut tu 81 xuong 52 check
# va van in "52/52 PASS". Mot cong co the tu thu nho lai thi khong con la cong.
if (-not (Test-Path $e2eHtml)) {
    Assert-Hard-Fail "Nhom 4 (E2E) phai chay duoc" "Khong tim thay $e2eHtml"
} elseif (-not (Test-Path $chromePath)) {
    Assert-Hard-Fail "Nhom 4 (E2E) phai chay duoc" "Khong tim thay Chrome/Edge headless - khong the kiem E2E xuat Excel va DOM"
} else {
    $tempOut = "$env:TEMP\e2e-out-test.html"
    # Xoa truoc: con sot output cua lan chay truoc thi Chrome loi van "PASS" tren file cu.
    if (Test-Path $tempOut) { Remove-Item $tempOut -Force }
    $e2eFull = (Get-Item $e2eHtml).FullName
    cmd /c "`"$chromePath`" --headless=old --dump-dom `"file:///$($e2eFull -replace '\\','/')`" 2>nul > `"$tempOut`""
    if (-not (Test-Path $tempOut)) {
        Assert-Hard-Fail "Nhom 4 (E2E): Chrome phai xuat duoc DOM" "Chrome khong tao ra $tempOut"
    } else {
        $outContent = Get-Content $tempOut -Raw -Encoding UTF8
        $match = [regex]::Match($outContent, '(?s)<div id="test-output">(.*?)</div>')
        if (-not $match.Success) {
            Assert-Hard-Fail "Nhom 4 (E2E): trang test phai tra ve khoi #test-output" "Khong tim thay <div id=`"test-output`"> trong DOM - 5 check E2E xuat Excel khong chay duoc"
        } else {
            $e2eData = ConvertFrom-Json $match.Groups[1].Value
            $mainProp = $e2eData.PSObject.Properties | Where-Object { $_.Name -like "Bao_Cao_GTM_Khuyen_Mai_*.xlsx" } | Select-Object -First 1; $mainFile = if ($mainProp) { $mainProp.Value } else { $null }
            $mkProp = $e2eData.PSObject.Properties | Where-Object { $_.Name -like "toan_thi_truong_*.xlsx" } | Select-Object -First 1; $mkFile = if ($mkProp) { $mkProp.Value } else { $null }

            Assert-Check "E2E: File Bao_Cao_GTM_Khuyen_Mai phai co DUNG 3 SHEETS" {
                $mainFile.sheetCount -eq 3
            } "Bao_Cao_GTM_Khuyen_Mai co $($mainFile.sheetCount) sheets thay vi 3 sheets"

            Assert-Check "E2E: File Bao_Cao_GTM_Khuyen_Mai phai chua 'Lich_Su_Theo_Dot_Quet'" {
                $mainFile.sheetNames -contains "Lich_Su_Theo_Dot_Quet"
            } "Thieu sheet Lich_Su_Theo_Dot_Quet trong Bao_Cao_GTM_Khuyen_Mai"

            # Truoc day ten test noi 94, dieu kien kiem >= 95, thong bao loi noi 96.
            # Gio lay tu mot nguon: masterSkuCount + 1 dong header.
            Assert-Check "E2E: Sheet Lich_Su_Theo_Dot_Quet phai co $($GateCfg.masterSkuCount) SKU + 1 dong header" {
                $historySheet = $mainFile.sheetsInfo | Where-Object { $_.name -eq "Lich_Su_Theo_Dot_Quet" }
                $historySheet.rowCount -eq ($GateCfg.masterSkuCount + 1)
            } "Sheet Lich_Su_Theo_Dot_Quet co $(($mainFile.sheetsInfo | Where-Object { $_.name -eq 'Lich_Su_Theo_Dot_Quet' }).rowCount) dong, mong doi $($GateCfg.masterSkuCount + 1)"

            Assert-Check "E2E: Sheet Lich_Su_Theo_Dot_Quet phai chua cot ngay 19-Oct" {
                $historySheet = $mainFile.sheetsInfo | Where-Object { $_.name -eq "Lich_Su_Theo_Dot_Quet" }
                $historySheet.header -contains "19-Oct"
            } "Sheet Lich_Su_Theo_Dot_Quet thieu cot ngay 19-Oct"

            Assert-Check "E2E: File toan_thi_truong phai co DUNG 3 SHEETS (them ca Lich_Su_Theo_Dot_Quet)" {
                $mkFile.sheetCount -eq 3 -and ($mkFile.sheetNames -contains "Lich_Su_Theo_Dot_Quet")
            } "toan_thi_truong khong co dung 3 sheets kem Lich_Su_Theo_Dot_Quet"
        }
    }

    # Kiem tra truc tiep DOM cua index.html va promotion tgdd.html xem ca 2 bien the A7 Pro 5G co render day du so lieu rieng biet hay khong
    $domCheckFiles = @("index.html", "promotion tgdd.html")
    foreach ($dcf in $domCheckFiles) {
        $fullDcf = (Get-Item $dcf).FullName
        $tempDcf = "$env:TEMP\dom_check_$($dcf -replace '[^\w]','_').html"
        cmd /c "`"$chromePath`" --headless=old --dump-dom `"file:///$fullDcf`" 2>nul > `"$tempDcf`""
        if (Test-Path $tempDcf) {
            $domContent = Get-Content $tempDcf -Raw -Encoding UTF8
            $a7_6_256 = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="A7 Pro 5G 6GB/256GB"[^>]*>(.*?)</tr>')
            $a7_8_128 = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="A7 Pro 5G 8GB/128GB"[^>]*>(.*?)</tr>')
            
            Assert-Check "DOM E2E: $dcf phai render rieng biet A7 Pro 5G 6GB/256GB (Gia offline 13.990.000, KM 500.000)" {
                $a7_6_256.Success -and 
                ($a7_6_256.Groups[1].Value -match '13\.990\.000') -and 
                ($a7_6_256.Groups[1].Value -match '500\.000') -and
                ($a7_6_256.Groups[1].Value -notmatch '<td>–</td>\s*<td>–</td>')
            } "$dcf bi loi thieu so lieu hoac khong render cho A7 Pro 5G 6GB/256GB"

            $v80_256 = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="V80 Lite 5G 6GB/256GB"[^>]*>(.*?)</tr>')
            $v80_128 = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="V80 Lite 5G 6GB/128GB"[^>]*>(.*?)</tr>')

            Assert-Check "DOM E2E: $dcf phai render rieng biet V80 Lite 5G 6GB/256GB (Gia offline hop le, khong de trong)" {
                $v80_256.Success -and 
                ($v80_256.Groups[1].Value -match '14\.990\.000') -and 
                ($v80_256.Groups[1].Value -notmatch '<td>–</td>\s*<td>–</td>')

            } "$dcf bi loi thieu so lieu hoac khong render cho V80 Lite 5G 6GB/256GB"

            Assert-Check "DOM E2E: $dcf phai render rieng biet V80 Lite 5G 6GB/128GB (Gia offline hop le, khong de trong)" {
                $v80_128.Success -and 
                ($v80_128.Groups[1].Value -match '12\.990\.000') -and 
                ($v80_128.Groups[1].Value -notmatch '<td>–</td>\s*<td>–</td>')

            } "$dcf bi loi thieu so lieu hoac khong render cho V80 Lite 5G 6GB/128GB"

            Assert-Check "DOM E2E: $dcf phai render rieng biet A7 Pro 5G 8GB/128GB (Gia offline 11.870.000, KM 1.620.000)" {
                $a7_8_128.Success -and 
                ($a7_8_128.Groups[1].Value -match '11\.870\.000') -and 
                ($a7_8_128.Groups[1].Value -match '1\.620\.000') -and
                ($a7_8_128.Groups[1].Value -notmatch '<td>–</td>\s*<td>–</td>')
            } "$dcf bi loi thieu so lieu hoac khong render cho A7 Pro 5G 8GB/128GB"

            Assert-Check "DOM E2E: $dcf tuyet doi khong hien thi banner canh bao tang gia ao A08 4GB/64GB" {
                ($domContent -notmatch "A08 4GB/64GB:\s*4\.790\.000.*5\.590\.000") -and
                ($domContent -notmatch "26-10-2026.*tang gia den")
            } "$dcf van con hien thi banner canh bao tang gia ao A08 4GB/64GB"
            Assert-Check "DOM E2E: $dcf tuyet doi khong render dong tang gia ao Galaxy A18 4G/128GB" {
                ($domContent -notmatch '<td[^>]*>\s*Galaxy A18 4G/128GB\s*</td>') -and
                ($domContent -notmatch 'data-m="Galaxy A18 4G/128GB"')
            } "$dcf van con hien thi dong tang gia ao Galaxy A18 4G/128GB"

            $a57Row = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="A57 5G 12GB/256GB"[^>]*>(.*?)</tr>')
            # Loi cu: scriptblock co HAI cau lenh roi nhau nen tra ve mang @(x, y).
            # `$result -eq $true` tren mang luon cho ra mang khac rong => test LUON PASS,
            # ke ca khi dong khong he duoc render ($a57Row.Success = $false).
            Assert-Check "DOM E2E: $dcf phai an to vang va bo co RRP tang cho Samsung A57 (tang > 15 ngay)" {
                $a57Row.Success -and ($a57Row.Groups[1].Value -notmatch "badge rrp")
            } "$dcf van hien thi to vang hoac co RRP tang cho Samsung A57 du da qua 15 ngay (hoac khong render duoc dong nay)"

            $r16Row = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="16 5G 8GB/256GB"[^>]*>(.*?)</tr>')
            Assert-Check "DOM E2E: $dcf phai an to vang va bo co RRP tang cho Realme 16 khi da qua 15 ngay (tu 21-Oct)" {
                $r16Row.Success -and ($r16Row.Groups[1].Value -notmatch "badge rrp")
            } "$dcf khong an to vang hoac van con co RRP tang cho Realme 16 (hoac khong render duoc dong nay)"

            $redmiRow = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="Redmi 17 4G 6GB/256GB"[^>]*>(.*?)</tr>')
            Assert-Check "DOM E2E: $dcf phai render gia online Redmi 17 4G 6GB/256GB dung (khong tru nham choice 200k)" {
                $redmiRow.Success -and 
                ($redmiRow.Groups[1].Value -match '5\.780\.000|5\.790\.000|5\.840\.000|5\.990\.000|6\.790\.000|7\.290\.000') -and
                ($redmiRow.Groups[1].Value -notmatch '5\.580\.000|6\.590\.000')
            } "$dcf hien thi sai gia online cho Redmi 17 4G 6GB/256GB"

            $a18Row = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="Galaxy A18 6GB/128GB"[^>]*>(.*?)</tr>')
            Assert-Check "DOM E2E: $dcf phai hien thi Galaxy A18 6GB/128GB la kenh Mass (RRP 7.190.000)" {
                $a18Row.Success -and 
                ($a18Row.Groups[1].Value -match 'class="badge mass">Mass<') -and
                ($a18Row.Groups[1].Value -match '7\.190\.000')
            } "$dcf khong hien thi Galaxy A18 6GB/128GB kenh Mass RRP 7.190.000"

            $renoRow = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="Reno16F 5G 8GB/256GB"[^>]*>(.*?)</tr>')
            Assert-Check "DOM E2E: $dcf phai hien thi Reno16F 5G 8GB/256GB la kenh Mass" {
                $renoRow.Success -and 
                ($renoRow.Groups[1].Value -match 'class="badge mass">Mass<')
            } "$dcf khong hien thi Reno16F 5G 8GB/256GB la kenh Mass"

            Assert-Check "DOM E2E: $dcf phai render du 5 model Realme C100/C100x trong tab Lich su tang gia T11" {
                ($domContent -match 'C100x 6GB/128GB') -and
                ($domContent -match 'C100 4G 6GB/128GB') -and
                ($domContent -match 'C100 4G 8GB/128GB') -and
                ($domContent -match 'C100 8GB/256GB') -and
                ($domContent -match 'C100x 4GB/128GB')
            } "$dcf khong render du 5 model Realme C100/C100x tang gia T11"
        }
    }
}

# ------------------------------------------------------------------------------
# TỔNG KẾT
# ------------------------------------------------------------------------------
Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "KET QUA KIEM TRA: $PassedChecks / $TotalChecks PASS ($FailedChecks FAILED)" -ForegroundColor $(if ($FailedChecks -eq 0) { "Green" } else { "Red" })
Write-Host "=================================================================" -ForegroundColor Cyan

if ($FailedChecks -gt 0) {
    exit 1
} else {
    exit 0
}

