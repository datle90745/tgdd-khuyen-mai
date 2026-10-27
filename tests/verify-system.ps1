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

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   BAT DAU KIEM TRA TOAN BO HE THONG THEO AGENT-SKILLS GATES     " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

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

    Assert-Check "Danh sach san pham trong products.csv phai co du 95 dong du lieu SKU" {
        $csvLines = (Get-Content "scraper/products.csv").Count
        $csvLines -ge 96 # 1 header + 95 SKU
    } "products.csv co it hon 95 SKU"

    Assert-Check "scraper/products.csv phai chua model chuan 'A7 Pro 5G 6GB/256GB' va 'A7 Pro 5G 8GB/128GB'" {
        $csvText = Get-Content "scraper/products.csv" -Raw -Encoding UTF8
        ($csvText -match 'A7 Pro 5G 6GB/256GB') -and ($csvText -match 'A7 Pro 5G 8GB/128GB') -and ($csvText -notmatch 'A7 Pro 5G 8GB/256GB')
    } "products.csv khong chua 'A7 Pro 5G 6GB/256GB' hoac van con ma loi 'A7 Pro 5G 8GB/256GB'"

    Assert-Check "data/links.js phai chua link cho 'A7 Pro 5G 6GB/256GB' va 'A7 Pro 5G 8GB/128GB'" {
        $linksText = Get-Content "data/links.js" -Raw -Encoding UTF8
        ($linksText -match '"A7 Pro 5G 6GB/256GB"') -and ($linksText -match '"A7 Pro 5G 8GB/128GB"')
    } "data/links.js thieu key 'A7 Pro 5G 6GB/256GB' hoac 'A7 Pro 5G 8GB/128GB'"

    Assert-Check "data/latest.js phai co 'A7 Pro 5G 6GB/256GB' active (red 12.990.000, PMH 1.500.000) va 'A7 Pro 5G 8GB/128GB' active" {
        $latestText = Get-Content "data/latest.js" -Raw -Encoding UTF8
        ($latestText -match '"model"\s*:\s*"A7 Pro 5G 6GB/256GB"[^}]*"red"\s*:\s*12990000' -and $latestText -match '"model"\s*:\s*"A7 Pro 5G 6GB/256GB"[^}]*"pmh"\s*:\s*1500000') -and
        ($latestText -match '"model"\s*:\s*"A7 Pro 5G 8GB/128GB"[^}]*"status"\s*:\s*"active"')
    } "data/latest.js thieu hoac sai so lieu A7 Pro 5G cac bien the"

    Assert-Check "data/latest.js phai co 'V80 Lite 5G 6GB/256GB' (RRP 14.990.000, PMH 700.000) va 'V80 Lite 5G 6GB/128GB' (RRP 12.990.000, PMH 700.000)" {
        $latestText = Get-Content "data/latest.js" -Raw -Encoding UTF8
        ($latestText -match '"model"\s*:\s*"V80 Lite 5G 6GB/256GB"[^}]*"rrp"\s*:\s*14990000' -and $latestText -match '"model"\s*:\s*"V80 Lite 5G 6GB/256GB"[^}]*"pmh"\s*:\s*700000') -and
        ($latestText -match '"model"\s*:\s*"V80 Lite 5G 6GB/128GB"[^}]*"rrp"\s*:\s*12990000' -and $latestText -match '"model"\s*:\s*"V80 Lite 5G 6GB/128GB"[^}]*"pmh"\s*:\s*700000')
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

    Assert-Check "data/scans.js dot quet 26-Oct phai co A08 4GB/64GB voi RRP 4.790.000" {
        $scansText = Get-Content "data/scans.js" -Raw -Encoding UTF8
        $raw = $scansText -replace "^\s*/\*.*?\*/\s*", "" -replace "^\s*window\.SCANS\s*=\s*", ""
        $raw = $raw.TrimEnd(" ;`r`n")
        $scansObj = $raw | ConvertFrom-Json
        $s26Obj = $scansObj | Where-Object { $_.date -eq "26-Oct" }
        $a08 = $s26Obj.rows | Where-Object { $_.model -eq "A08 4GB/64GB" }
        $a08.rrp -eq 4790000
    } "data/scans.js 26-Oct sai RRP A08 4GB/64GB"

    Assert-Check "canonKey() trong index.html tuyet doi khong co quy tac hack dong bo bien the a7pro5g" {
        $idxText = Get-Content "index.html" -Raw -Encoding UTF8
        $idxText -notmatch 'oppo_a7pro5g8gb256gb'
    } "index.html van con chua ma hack canonKey dong bo bien the a7pro5g"
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

if ((Test-Path $e2eHtml) -and (Test-Path $chromePath)) {
    $tempOut = "$env:TEMP\e2e-out-test.html"
    cmd /c "`"$chromePath`" --headless=old --dump-dom `"file:///c:/Users/toquo/Documents/antigravity/fervent-raman/tests/test-excel-e2e.html`" 2>nul > `"$tempOut`""
    if (Test-Path $tempOut) {
        $outContent = Get-Content $tempOut -Raw -Encoding UTF8
        $match = [regex]::Match($outContent, '(?s)<div id="test-output">(.*?)</div>')
        if ($match.Success) {
            $e2eData = ConvertFrom-Json $match.Groups[1].Value
            $mainProp = $e2eData.PSObject.Properties | Where-Object { $_.Name -like "Bao_Cao_GTM_Khuyen_Mai_*.xlsx" } | Select-Object -First 1; $mainFile = if ($mainProp) { $mainProp.Value } else { $null }
            $mkProp = $e2eData.PSObject.Properties | Where-Object { $_.Name -like "toan_thi_truong_*.xlsx" } | Select-Object -First 1; $mkFile = if ($mkProp) { $mkProp.Value } else { $null }

            Assert-Check "E2E: File Bao_Cao_GTM_Khuyen_Mai phai co DUNG 3 SHEETS" {
                $mainFile.sheetCount -eq 3
            } "Bao_Cao_GTM_Khuyen_Mai co $($mainFile.sheetCount) sheets thay vi 3 sheets"

            Assert-Check "E2E: File Bao_Cao_GTM_Khuyen_Mai phai chua 'Lich_Su_Theo_Dot_Quet'" {
                $mainFile.sheetNames -contains "Lich_Su_Theo_Dot_Quet"
            } "Thieu sheet Lich_Su_Theo_Dot_Quet trong Bao_Cao_GTM_Khuyen_Mai"

            Assert-Check "E2E: Sheet Lich_Su_Theo_Dot_Quet phai co du 94 SKU Master List (95 dong gom header)" {
                $historySheet = $mainFile.sheetsInfo | Where-Object { $_.name -eq "Lich_Su_Theo_Dot_Quet" }
                $historySheet.rowCount -ge 95
            } "So dong trong Lich_Su_Theo_Dot_Quet khong bang 96"

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
            
            Assert-Check "DOM E2E: $dcf phai render rieng biet A7 Pro 5G 6GB/256GB (Gia offline 12.990.000, KM 1.500.000)" {
                $a7_6_256.Success -and 
                ($a7_6_256.Groups[1].Value -match '12\.990\.000') -and 
                ($a7_6_256.Groups[1].Value -match '1\.500\.000') -and
                ($a7_6_256.Groups[1].Value -notmatch '<td>–</td>\s*<td>–</td>')
            } "$dcf bi loi thieu so lieu hoac khong render cho A7 Pro 5G 6GB/256GB"

            $v80_256 = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="V80 Lite 5G 6GB/256GB"[^>]*>(.*?)</tr>')
            $v80_128 = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="V80 Lite 5G 6GB/128GB"[^>]*>(.*?)</tr>')

            Assert-Check "DOM E2E: $dcf phai render rieng biet V80 Lite 5G 6GB/256GB (RRP 14.990.000, PMH 700.000)" {
                $v80_256.Success -and 
                ($v80_256.Groups[1].Value -match '14\.990\.000') -and 
                ($v80_256.Groups[1].Value -match '14\.290\.000') -and 
                ($v80_256.Groups[1].Value -match '700\.000')
            } "$dcf bi loi thieu so lieu hoac khong render cho V80 Lite 5G 6GB/256GB"

            Assert-Check "DOM E2E: $dcf phai render rieng biet V80 Lite 5G 6GB/128GB (RRP 12.990.000, PMH 700.000)" {
                $v80_128.Success -and 
                ($v80_128.Groups[1].Value -match '12\.990\.000') -and 
                ($v80_128.Groups[1].Value -match '12\.290\.000') -and 
                ($v80_128.Groups[1].Value -match '700\.000')
            } "$dcf bi loi thieu so lieu hoac khong render cho V80 Lite 5G 6GB/128GB"

            Assert-Check "DOM E2E: $dcf phai render rieng biet A7 Pro 5G 8GB/128GB (Gia offline hop le, khong de trong)" {
                $a7_8_128.Success -and 
                ($a7_8_128.Groups[1].Value -match '11\.940\.000|12\.140\.000') -and 
                ($a7_8_128.Groups[1].Value -match '1\.550\.000|1\.350\.000') -and
                ($a7_8_128.Groups[1].Value -notmatch '<td>–</td>\s*<td>–</td>')
            } "$dcf bi loi thieu so lieu hoac khong render cho A7 Pro 5G 8GB/128GB"

            Assert-Check "DOM E2E: $dcf tuyet doi khong hien thi banner canh bao tang gia ao A08 4GB/64GB" {
                ($domContent -notmatch "A08 4GB/64GB:\s*4\.790\.000.*5\.590\.000") -and
                ($domContent -notmatch "26-10-2026.*tang gia den")
            } "$dcf van con hien thi banner canh bao tang gia ao A08 4GB/64GB"

            $a57Row = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="A57 5G 12GB/256GB"[^>]*>(.*?)</tr>')
            Assert-Check "DOM E2E: $dcf phai an to vang va bo co RRP tang cho Samsung A57 (tang > 15 ngay)" {
                $a57Row.Success -and 
                ($a57Row.Groups[1].Value -notmatch 'rrpup') -and 
                ($a57Row.Groups[1].Value -notmatch 'RRP tÄƒng')
            } "$dcf van hien thi to vang hoac co RRP tang cho Samsung A57 du da qua 15 ngay"

            $r16Row = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="16 5G 8GB/256GB"[^>]*>(.*?)</tr>')
            Assert-Check "DOM E2E: $dcf phai to vang va co co RRP tang cho Realme 16 (tang <= 15 ngay)" {
                $r16Row.Success -and 
                ($r16Row.Groups[1].Value -match 'rrpup') -and 
                ($r16Row.Groups[1].Value -match 'RRP tÄƒng')
            } "$dcf khong to vang hoac thieu co RRP tang cho Realme 16 (trong vong 15 ngay)"

            $redmiRow = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="Redmi 17 4G 6GB/256GB"[^>]*>(.*?)</tr>')
            Assert-Check "DOM E2E: $dcf phai render gia online Redmi 17 4G 6GB/256GB dung 6.790.000" {
                $redmiRow.Success -and 
                ($redmiRow.Groups[1].Value -match '6\.790\.000') -and
                ($redmiRow.Groups[1].Value -notmatch '6\.590\.000')
            } "$dcf hien thi sai gia online cho Redmi 17 4G 6GB/256GB (khong phai 6.790.000)"

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
