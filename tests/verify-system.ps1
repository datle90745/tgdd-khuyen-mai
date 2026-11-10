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
Write-Host "   Danh sach cao: $($GateCfg.crawlSkuCount) SKU | Master List bao cao: $($GateCfg.masterListCount) SKU | Hom nay (VN): $($TodayVN.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
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
    $retained = Get-ChildItem "data/scans" -Filter "scan_*.json" | Where-Object {
        $dt = [datetime]($_.BaseName -replace 'scan_', '')
        $dt.DayOfWeek -eq 'Monday' -or $dt.DayOfWeek -eq 'Friday'
    } | Sort-Object Name | Select-Object -Last $GateCfg.scansJsRetention
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

    # Cat than mot ham Python ra de khang dinh kiem DUNG TRONG ham do, thay vi kiem "co chuoi
    # nay o dau do trong ca file". Nhieu khang dinh truoc day sai vi ly do nay: vi du kiem
    # `-match 'sau'` de chung minh FLASH_KEYWORDS_RE co tu khoa "Ket thuc sau", trong khi chu
    # "sau" xuat hien trong hang chuc tu tieng Viet khac khap file.
    function Get-PyBlock($text, $header) {
        $i = $text.IndexOf($header)
        if ($i -lt 0) { return "" }
        $rest = $text.Substring($i + $header.Length)
        $m = [regex]::Match($rest, '(?m)^(?:def |class |[A-Z_]+\s*=)')
        if ($m.Success) { return $rest.Substring(0, $m.Index) }
        return $rest
    }

    Assert-Check "Quy tac Flash Sale: 'Uu dai ONLINE' va 'Ket thuc sau' phai nam trong FLASH_KEYWORDS_RE" {
        # Kiem trong CHINH than regex, khong phai o dau do trong file.
        $re = Get-PyBlock $scanContent 'FLASH_KEYWORDS_RE = re.compile('
        ($re.Length -gt 0) -and ($re -match 'ONLINE') -and ($re -match 'th[^|]*c sau') -and
        ($re -match 'flash\\s\*sale') -and ($re -match 'su[^|]*t')
    } "FLASH_KEYWORDS_RE thieu tu khoa Flash Sale (kiem trong chinh than re.compile, khong phai ca file)"

    Assert-Check "Quy tac Flash Sale: Phai co BANNER CAM (ORANGE_BANNER_RE / has_banner_cam)" {
        # ORANGE_BANNER_RE phai thuc su chua lop/mau cam, VA phai la thu nuoi has_banner_cam.
        $re = Get-PyBlock $scanContent 'ORANGE_BANNER_RE = re.compile('
        ($re.Length -gt 0) -and ($re -match 'bg-fs') -and ($re -match 'box_saving') -and
        ($re -match 'orange') -and
        ($scanContent -cmatch '(?s)has_banner_cam\s*=\s*bool\((?:(?!\n\s*\n).)*?ORANGE_BANNER_RE')
    } "ORANGE_BANNER_RE thieu lop/mau cam, hoac has_banner_cam khong duoc nuoi boi ORANGE_BANNER_RE"

    Assert-Check "Quy tac Flash Sale: banner = has_banner_cam and has_flash_kw" {
        $scanContent -match 'banner\s*=\s*bool\(has_banner_cam\s+and\s+has_flash_kw\)'
    } "Dieu kien banner flash sale phai ket hop ca Banner Cam va Tu khoa Flash Sale"

    Assert-Check "build_result phai tra ve truong banner va choice_in_red" {
        $scanContent -match '"banner":\s*bool\(banner\)' -and $scanContent -match '"choice_in_red":\s*choice_in_red'
    } "build_result thieu truong banner hoac choice_in_red"

    Assert-Check "enforce_domain_invariants phai giu nguyen Flash Sale khi co banner hoac rule flash_chon1" {
        $scanContent -match 'has_banner\s*=\s*bool\(row\.get\("banner"\)\s+or\s+row\.get\("rule"\)\s*==\s*"flash_chon1"'
    } "enforce_domain_invariants khong kiem tra rule flash_chon1 hoac banner"

    Assert-Check "Fallback _CATALOG_ITEMS khong duoc ghi de may dang co Flash Sale" {
        $scanContent -match 'result\.get\("rule"\)\s*!=\s*"flash_chon1"'
    } "Fallback _CATALOG_ITEMS ghi de nham may Flash Sale"

    Assert-Check "Du lieu dot quet hom nay: moi may co Flash Sale (flash_chon1) phai co PMH bang choice va banner=true" {
        $jsonText = (Get-Content "data/latest.js" -Raw -Encoding UTF8) -replace '^/\*.*?\*/\s*window\.LATEST\s*=\s*', '' -replace ';?\s*$', ''
        $latest = $jsonText | ConvertFrom-Json
        $flashRows = $latest.rows | Where-Object { $_.rule -eq "flash_chon1" }
        if ($flashRows.Count -eq 0) { return $true }
        foreach ($r in $flashRows) {
            $exp = if ($r.choice -ne $null) { $r.choice } else { 0 }
            if ($r.pmh -ne $exp) { return $false }
            if ($r.choice -eq 0 -and $r.pmh -ne 0) { return $false }
            if ($r.banner -ne $true) { return $false }
        }
        return $true
    } "Phat hien model flash_chon1 co PMH lech choice hoac thieu banner=true"

    # Khang dinh nay truoc day chi kiem `_CATALOG_ITEMS = {}` co ton tai hay khong - tuc la no
    # KHONG he kiem thu ma chinh ten no noi. No bao PASS suot trong khi ba dong ngay ben duoi
    # ep cung 6 con so gia cho a7-pro. Nay kiem dung thu can kiem: gan gia bang SO VIET THANG
    # vao _CATALOG_ITEMS["<khoa chuoi>"].
    Assert-Check "Scraper scan_tgdd.py khong duoc chua gia hardcode trong _CATALOG_ITEMS" {
        ($scanContent -cmatch '_CATALOG_ITEMS\s*=\s*\{\}') -and
        ($scanContent -notmatch '(?m)^\s*_CATALOG_ITEMS\[\s*"[^"]+"\s*\]\s*=\s*\{\s*"red"\s*:\s*\d')
    } "Scraper scan_tgdd.py van con gia hardcode trong _CATALOG_ITEMS gay nguy co phuc hoi gia cu"

    # Khang dinh nay tung bi DAO CHIEU ngay 10-11-2026: ban goc doi PINNED_PRICES phai CO,
    # mot commit sau doi no phai KHONG CO. Hau qua: A7 Pro 5G 256GB (ca hai ban) mat sach so
    # lieu tren bang, vi PDP cua chung la Marketing Landing Page khong bao gio render gia.
    # CONSTRAINTS 2.11 cam dao chieu mot khang dinh ma khong hoi nguoi dung.
    #
    # Moi lo cua ban dao chieu la DUNG va van duoc giu: khong duoc lay gia cu thay cho gia
    # live. Nen chot nay doi CA HAI dieu:
    #   1. Gia du phong phai ton tai (de dong landing page khong bi de trong), VA
    #   2. No chi duoc ap o buoc cuoi, va phai bi BO QUA khi dot nay cao duoc gia that.
    Assert-Check "Gia du phong chi la du phong: cao duoc gia that thi phai bo qua" {
        ($scanContent -cmatch 'PINNED_PRICES') -and
        ($scanContent -cmatch '(?m)^def apply_pinned_prices\(rows\):') -and
        # Phai chay SAU cac buoc xac minh, khong phai ghi de tu dau.
        ($scanContent -cmatch '(?s)rows = verify_flash_rows\(rows\).*?rows = apply_pinned_prices\(rows\)') -and
        # Phai co nhanh bo qua khi da cao duoc gia do that.
        ($scanContent -cmatch 'co_gia_that') -and
        ($scanContent -cmatch 'BO QUA gia du phong') -and
        # Dong duoc ap phai mang kind = "pin" de phan biet voi gia cao that.
        ($scanContent -cmatch '"kind":\s*"pin"')
    } "Gia du phong bi go mat (dong landing page se de trong), hoac no da thanh ghi de thay vi du phong"
    Assert-Check "Quet mot phan khong duoc tron gia cu roi dong dau gio moi" {
        ($scanContent -notmatch 'merge_into_today') -and
        ($scanContent -match 'if partial:\s*sys\.exit\(')
    } "Scraper van co the ghi ban quet mot phan vao du lieu hien tai"
    # Chot chong cao nham bien the phai duoc KHAI BAO, khong viet thang ten model + con so.
    Assert-Check "Chot chong cao nham bien the phai nam o variant_guards.json, khong viet thang" {
        $p = "scraper/variant_guards.json"
        if (-not (Test-Path $p)) { return $false }
        $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $bad = @($j.entries | Where-Object {
            -not $_.model -or -not $_.wrong_rrp -or -not $_.correct_rrp -or
            -not $_.reason -or $_.reason.Length -lt 40
        })
        ($bad.Count -eq 0) -and
        ($scanContent -cmatch 'VARIANT_GUARDS') -and
        ($scanContent -cmatch 'vguard\["wrong_rrp"\]') -and
        # Khong con dieu kien so sanh ten model voi mot con so gia viet thang.
        ($scanContent -notmatch 'product\["model"\]\s*==\s*"[^"]+"\s*and\s*scraped_rrp\s*==\s*\d')
    } "Chot chong cao nham bien the con viet thang ten model + con so trong .py, hoac muc trong variant_guards.json thieu truong/bang chung"

    # Nhan cot ngay ("09-Nov") la KHOA dung xuyen suot data.js, scans.js, latest.js, sheet
    # Excel va ca cong kiem tra. strftime("%b") lay ten thang theo LOCALE cua may dang chay -
    # mot runner co locale khac se sinh nhan khac va lam lech toan bo ma khong co gi bao.
    Assert-Check "Nhan ngay phai khong phu thuoc locale (cam strftime %b)" {
        $mkt = Get-Content "scraper/scan_market.py" -Raw -Encoding UTF8
        $alr = Get-Content "scraper/alerts.py" -Raw -Encoding UTF8
        ($alr -cmatch 'MONTH_ABBR') -and ($alr -cmatch '(?m)^def day_label\(dt\):') -and
        ($scanContent -notmatch '%d-%b') -and ($mkt -notmatch '%d-%b') -and
        ($scanContent -cmatch 'alerts\.day_label\(') -and ($mkt -cmatch 'alerts\.day_label\(')
    } "Con cho sinh nhan ngay bang strftime(`"%d-%b`") - ten thang se doi theo locale cua may chay"

    # Loi phong (mojibake): van ban UTF-8 bi doc nham thanh Latin-1 roi ghi lai. Da don sach
    # 8 dong ngay 10-11-2026. Chot nay la BANH COC: chi duoc giam, khong duoc tang.
    Assert-Check "Khong duoc them dong loi phong (mojibake) vao file nguon" {
        # So sanh bang MA KY TU, khong viet ky tu la hay escape \uXXXX vao day: cong cu sua
        # file co the tu chuyen escape thanh ky tu that va lam hong chinh chot nay (da xay ra).
        $tong = 0
        foreach ($f in @('index.html', 'scraper/scan_market.py', 'scraper/scan_tgdd.py',
                         'scraper/alerts.py', 'scraper/bundle.py', 'data/data.js', 'CONSTRAINTS.md')) {
            if (-not (Test-Path $f)) { continue }
            foreach ($line in (Get-Content $f -Encoding UTF8)) {
                $ch = $line.ToCharArray()
                for ($k = 0; $k -lt $ch.Length - 1; $k++) {
                    $a = [int]$ch[$k]; $b = [int]$ch[$k + 1]
                    # 0xC3 / 0xC2 la dau hieu UTF-8 bi doc nham thanh Latin-1, theo sau la
                    # ky tu trong dai 0x80-0xFF hoac dai dau cau 0x2000-0x206F.
                    if (($a -eq 0xC3 -or $a -eq 0xC2) -and
                        (($b -ge 0x80 -and $b -le 0xFF) -or ($b -ge 0x2000 -and $b -le 0x206F))) {
                        $tong++
                        break
                    }
                }
            }
        }
        $tong -le [int]$GateCfg.maxMojibakeLines
    } "Co them dong loi phong trong file nguon - kiem lai encoding cua cong cu vua sua file (gate-config.maxMojibakeLines)"

    Assert-Check "Model cao loi trong cung ngay phai de trong PMH hien tai" {
        $idxText = Get-Content "index.html" -Raw -Encoding UTF8
        ($idxText -match 'x\.status==="error"') -and
        ($idxText -match 'r\.pmh\[col\]=null')
    } "Trang van mang PMH tu dot truoc trong cung ngay khi model cao loi"
    Assert-Check "Scraper khong duoc ghi de ket qua cao bang gia viet thang trong file .py" {
        $scanContent -notmatch '(?m)^\s*result\.update\(\{\s*$' -or
        $scanContent -notmatch '"rrp"\s*:\s*\d{7,}'
    } "scan_tgdd.py con khoi result.update({...}) mang so gia viet thang - gia phai den tu trang live"

    # CONSTRAINTS 2.7 bat buoc tra cuu lan cuoi qua danh muc TGDD khi khong tu do duoc ket qua.
    # Truoc day nhanh LOI (`return {"status": "error"}`) tra thang ve ma khong he goi chot chan -
    # dung luc no can nhat thi no khong chay. Cac dong status=error trong lich su deu chua bao
    # gio duoc tra cuu lai. Khang dinh nay kiem DUNG THU TU: last-check phai dung TRUOC cau
    # return error.
    Assert-Check "Cao LOI thi bat buoc tra cuu lan cuoi qua danh muc TGDD truoc khi bo cuoc" {
        $scanContent -cmatch '(?s)BRAND_HUB_LAST_CHECK.*?fetch_model_from_brand_hub\(slug\).*?return \{"status": "error"'
    } "scan_tgdd.py tra ve status=error ma khong tra cuu lan cuoi qua danh muc TGDD (CONSTRAINTS 2.7)"

    Assert-Check "Chot chan cuoi cung phai thu CA tab thuong hieu VA danh muc tong /dtdd" {
        ($scanContent -cmatch 'hub_urls\.append\(f"https://www\.thegioididong\.com/dtdd-\{b\}"\)') -and
        ($scanContent -cmatch 'hub_urls\.append\("https://www\.thegioididong\.com/dtdd"\)')
    } "fetch_model_from_brand_hub khong thu ca hai duong - CONSTRAINTS 2.7 chi dinh ca /dtdd lan tab thuong hieu"

    Assert-Check "Scraper scan_tgdd.py phai co ham fetch_model_from_brand_hub lam chot chan cuoi cung" {
        $scanContent -match 'def fetch_model_from_brand_hub\('
    } "Scraper scan_tgdd.py thieu ham fetch_model_from_brand_hub quet live tab brand TGDĐ"

    Assert-Check "Scraper scan_tgdd.py phai dung nguong minActivePct thay vi 50%" {
        $scanContent -match 'min_active_pct' -and $scanContent -notmatch 'ok\s*<\s*len\(products\)\s*\*\s*0\.5'
    } "Scraper scan_tgdd.py van con dung nguong 50% lam lot loi"

    Assert-Check "write_scans_js va write_latest_js phai luu truong banner" {
        $scanContent -match 'keys\s*=\s*\([^)]*"banner"[^)]*\)'
    } "write_scans_js hoac write_latest_js thieu truong banner"

    Assert-Check "Cac file dong goi offline (promotion tgdd) phai dong bo du lieu day du va tren 1MB" {
        $f1 = "promotion tgdd.html"
        $f2 = "promotion tgdd standalone.html"
        $f3 = "promotion tgdd/promotion tgdd.html"
        (Test-Path $f1) -and (Test-Path $f2) -and (Test-Path $f3) -and ((Get-Item $f1).Length -gt 1MB) -and ((Get-Item $f2).Length -gt 1MB) -and ((Get-Item $f3).Length -gt 1MB)
    } "File offline dong goi bi thieu hoac dung luong qua nho"

    Assert-Check "Quy tac PMH khi co Banner Cam: PMH = choice (flash_chon1)" {
        $scanContent -match 'pmh,\s*rule\s*=\s*choice,\s*"flash_chon1"'
    } "Thieu quy tac PMH = choice khi co banner cam"

    Assert-Check "Quy tac Scraper: Ham extract_choice phai tach rieng va xu ly chon 1 trong, lstGift" {
        # `lstGift` phai nam TRONG than extract_choice, khong phai o bat ky dau trong file.
        $fn = Get-PyBlock $scanContent 'def extract_choice('
        ($fn.Length -gt 0) -and ($fn -match 'lstGift') -and ($fn -match 'n 1 trong')
    } "Thieu ham extract_choice xu ly tong the cac dang choice (ca 'Chon 1 trong' lan lstGift phai nam trong chinh ham do)"

    Assert-Check "Quy tac Scraper: write_scans_js phai luu giu dung cac dot quet Thu Hai va Thu Sau theo KEEP_WEEKDAYS" {
        $scanContent -match 'if\s+day\.weekday\(\)\s+not\s+in\s+alerts\.KEEP_WEEKDAYS'
    } "write_scans_js phai su dung alerts.KEEP_WEEKDAYS de giu dung dot quet Thu Hai va Thu Sau"

    Assert-Check "Quy tac Alerts: load_base_rrp_map phai nap ca baseline data.js va scans.js" {
        # Ca HAI nguon phai duoc doc trong CHINH than ham, khong phai o dau do trong alerts.py.
        $alertsText = Get-Content "scraper/alerts.py" -Raw -Encoding UTF8
        # Phai bat CAU LENH DOC THAT (`DATA_DIR / "scans.js"`), khong phai chuoi "scans.js"
        # bat ky - vi docstring cua chinh ham nay cung co chu "data/scans.js", nen kiem long
        # se khop vao loi van mo ta thay vi vao hanh vi. Dung lop loi cua chot HOI QUY khop
        # nham dong console.log.
        $fn = Get-PyBlock $alertsText 'def load_base_rrp_map():'
        ($fn.Length -gt 0) -and ($fn -cmatch '_base_text\(\)') -and
        ($fn -cmatch 'DATA_DIR\s*/\s*"scans\.js"') -and ($fn -cmatch 'window\\\.SCANS')
    } "load_base_rrp_map phai nap ca baseline data.js va scans.js ngay trong than ham (phai la cau lenh doc that, khong phai chu trong docstring)"

    # CONSTRAINTS 2.6 khong noi "phai co ham", no noi "HANG NGAY SAU KHI hoan thanh dot quet,
    # scraper phai thuc hien buoc fast_check_o3". Khang dinh cu chi kiem `def fast_check_o3(`
    # co ton tai - ham ton tai ma khong ai goi thi van bao PASS, dung lop loi cua last-check.
    Assert-Check "Quy tac Fast-Check: fast_check_o3 phai duoc GOI sau khi luu dot quet" {
        ($scanContent -cmatch '(?m)^\s*def fast_check_o3\(') -and
        ($scanContent -cmatch '(?m)^\s+fast_check_o3\(scan\)') -and
        # Phai goi SAU khi da ghi scan ra dia, nguoc lai thi doi soat tren du lieu chua luu.
        ($scanContent -cmatch '(?s)write_latest_js\(scan\).*?fast_check_o3\(scan\)')
    } "fast_check_o3 khong duoc goi sau khi luu dot quet - CONSTRAINTS 2.6 bat buoc doi soat #o=3 hang ngay"

    Assert-Check "CONSTRAINTS.md phai quy dinh chuan tham chieu Ground Truth dtdd#o=3" {
        $cText = Get-Content "CONSTRAINTS.md" -Raw -Encoding UTF8
        ($cText -match 'dtdd#o=3') -and ($cText -match 'Ground Truth')
    } "CONSTRAINTS.md thieu muc 2.6 ve chuan tham chieu Ground Truth dtdd#o=3"

    Assert-Check "CONSTRAINTS.md phai quy dinh chot chan cuoi cung tab brand TGDD o muc 2.7" {
        $cText = Get-Content "CONSTRAINTS.md" -Raw -Encoding UTF8
        ($cText -match '2.7.') -and ($cText -match '/dtdd') -and ($cText -match 'SKU')
    } "CONSTRAINTS.md thieu muc 2.7 ve chot chan cuoi cung tab brand TGDD"

    # Bay cu: `red = row.get("red") or rrp`. Trang loi -> red=0 -> am tham gan red=rrp
    # -> diff=0 -> PMH boc hoi, ma moi truong con lai van nhat quan nen khong check nao bat duoc.
    # Neo vao dau DONG LENH that, khong tinh dong comment - ban than comment trong
    # scan_tgdd.py co nhac lai bay cu de giai thich tai sao no bi bo.
    Assert-Check "enforce_domain_invariants KHONG duoc suy ra gia do tu RRP khi thieu gia" {
        $scanContent -notmatch '(?m)^\s*red\s*=\s*row\.get\("red"\)\s*or\s*rrp'
    } "scan_tgdd.py da quay lai bay suy gia do tu rrp - thieu gia phai ha xuong no_price, khong duoc doan"

    Assert-Check "enforce_domain_invariants phai ha status xuong no_price khi thieu rrp/red" {
        # Nhanh ha no_price phai nam TRONG enforce_domain_invariants, khong phai o ham khac.
        $fn = Get-PyBlock $scanContent 'def enforce_domain_invariants(row):'
        ($fn.Length -gt 0) -and ($fn -match 'row\["status"\]\s*=\s*"no_price"') -and
        ($fn -match 'if not rrp or not red')
    } "enforce_domain_invariants khong con nhanh ha no_price khi khong doc duoc gia"

    Assert-Check "Moi lan hieu chinh gia do phai in log, khong sua ground truth trong im lang" {
        # Phai in log NGAY TRONG ham sua gia, va phai co du ca hai cho sua: ha no_price va
        # lam tron ve hang nghin. Truoc day chi kiem chuoi "[INVARIANT]" co o dau do trong file.
        $fn = Get-PyBlock $scanContent 'def enforce_domain_invariants(row):'
        $logs = ([regex]::Matches($fn, '\[INVARIANT\]')).Count
        ($fn.Length -gt 0) -and ($logs -ge 2) -and
        ($fn -cmatch '(?s)if not rrp or not red:.*?\[INVARIANT\]') -and
        ($fn -cmatch '(?s)red % 1000 != 0:.*?\[INVARIANT\]')
    } "scan_tgdd.py lam tron / doi gia ma khong in log [INVARIANT] ngay trong enforce_domain_invariants"

    Assert-Check "CONSTRAINTS.md phai mo ta HAI danh sach tach biet va tro ve tests/gate-config.json" {
        $cText = Get-Content "CONSTRAINTS.md" -Raw -Encoding UTF8
        ($cText -match 'tests/gate-config\.json') -and ($cText -match 'crawlSkuCount') -and ($cText -match 'masterListCount')
    } "CONSTRAINTS.md chua mo ta quan he danh sach CAO vs Master List BAO CAO theo gate-config.json"

    # --- Chot chan cho chinh NGUYEN NHAN GOC ---
    # Lich su du an: 24 khang dinh da bi XOA am tham, va 1 khang dinh bi DAO NGUOC
    # (-notmatch <-> -match tren cung regex KEEP_WEEKDAYS). Ca hai trang thai deu bao
    # 100% PASS, nen khong ai biet quy tac nao moi la thu nguoi dung yeu cau.
    Assert-Check "So khang dinh khong duoc tut xuong duoi nguong da chot" {
        $script:TotalChecks -ge 1 -and $GateCfg.minAssertions -ge 1
        $allNames = (Select-String -Path "tests/verify-system.ps1" -Pattern 'Assert-(?:Check|Hard-Fail)\s+"' -AllMatches).Matches.Count
        $allNames -ge $GateCfg.minAssertions
    } "verify-system.ps1 chi con $((Select-String -Path 'tests/verify-system.ps1' -Pattern 'Assert-(?:Check|Hard-Fail)\s+"' -AllMatches).Matches.Count) khang dinh, duoi nguong $($GateCfg.minAssertions). Xoa khang dinh phai di kem ha minAssertions trong gate-config.json - de thay duoc trong diff."

    # Dung -cmatch (PHAN BIET HOA THUONG) va bat buoc co dau ':' - tuc la bat dung CAU
    # BAO LOI trong fail(), khong phai dong console.log mo ta.
    # Truoc day dung -match: PowerShell khong phan biet hoa thuong nen chot van PASS khi
    # chot that da bi go, chi can con dong log "[6] Hoi quy giua cac dot..." la du lua.
    Assert-Check "Circuit breaker phai con chot so sanh GIUA CAC DOT QUET" {
        $cb = Get-Content "tests/verify_scan.js" -Raw -Encoding UTF8
        ($cb -cmatch 'HOI QUY:') -and ($cb -cmatch 'HOI QUY DIEN RONG:') -and
        ($cb -cmatch 'CFG\.maxFlatZeroDrops') -and ($cb -cmatch 'known-zero-pmh')
    } "tests/verify_scan.js mat chot hoi quy giua cac dot - day la thu duy nhat bat duoc loi PDP landing page ghi de du lieu dung"

    Assert-Check "File xac nhan PMH=0 phai ton tai va moi muc phai co bang chung" {
        $p = "tests/known-zero-pmh.json"
        if (-not (Test-Path $p)) { return $false }
        $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $bad = @($j.entries | Where-Object { -not $_.model -or -not $_.since -or -not $_.rrp -or -not $_.reason -or $_.reason.Length -lt 20 })
        $bad.Count -eq 0
    } "tests/known-zero-pmh.json co muc thieu model/since/rrp hoac `reason` qua so sai - moi xac nhan phai ghi ro bang chung doi soat"

    # Loi 09-11-2026: khoi `if product["model"] in ("iPhone 18 Pro Max 256GB", "iPhone 18 Pro
    # 256GB"): result["status"] = "chua_mo_ban"` ghim cung trang thai, khong kem dieu kien nao,
    # nen hai model bao "chua mo ban" suot 24 dot lien tiep du TGDD da mo ban that.
    Assert-Check "Scraper khong duoc ep cung trang thai theo DANH SACH ten model" {
        $pyText = Get-Content "scraper/scan_tgdd.py" -Raw -Encoding UTF8
        $pyText -notmatch '(?m)^\s*if\s+product\["model"\]\s+in\s+\('
    } "scraper/scan_tgdd.py co khoi `if product[""model""] in (...)` ghi de ket qua cao that theo ten model - CONSTRAINTS 2.9 cam viet chot dich danh model"

    # Loi 09-11-2026: muc [5] chi so truong `date` nen ban sao co cung ngay nhung khac noi
    # dung tung dong van lot. Tu nay phai so TUNG DONG va phai CHAN, khong chi canh bao.
    Assert-Check "Circuit breaker phai so TUNG DONG cua ban sao long nhau va phai CHAN" {
        $cb = Get-Content "tests/verify_scan.js" -Raw -Encoding UTF8
        ($cb -cmatch 'BAN SAO LECH:') -and ($cb -cmatch 'nestedCopyPath') -and
        ($cb -cmatch "total_online") -and ($cb -cmatch 'nestedByModel')
    } "tests/verify_scan.js khong con so tung dong cua ban sao `promotion tgdd/data` - ban sao van bi git add moi dot nen no se phuc vu web voi so lieu khac"

    # Flash sale chay theo khung gio: KHONG duoc mac dinh, khong duoc be tu dot truoc sang.
    # Ca da gap: hub /flashsale duoc nap DUNG MOT LAN truoc vong lap roi dung cho ca 135 model
    # suot ~9-20 phut quet, nen mot anh chup cu quyet dinh trang thai flash cua ca dot.
    Assert-Check "Scraper phai QUET LAI tat ca model truoc khi luu, voi hub nap lai" {
        ($scanContent -cmatch '(?m)^def verify_flash_rows\(rows\):') -and
        ($scanContent -cmatch 'for r in rows if r.get\("url"\)') -and
        ($scanContent -cmatch '(?s)def verify_flash_rows\(rows\):.*?fetch_live_flashsale_slugs\(\)') -and
        ($scanContent -cmatch '(?m)^\s+rows = verify_flash_rows\(rows\)') -and
        # Phai goi TRUOC khi ghi file scan, nguoc lai thi quet lai cung vo nghia.
        ($scanContent -cmatch '(?s)rows = verify_flash_rows\(rows\).*?SCAN_DIR / f"scan_\{now\.date\(\)\.isoformat\(\)\}\.json"')
    } "scan_tgdd.py khong quet lai ung vien flash sale truoc khi luu - anh chup hub dau dot se quyet dinh trang thai flash cua ca dot"

    Assert-Check "Moi ket luan flash sale phai kem bang chung flash_src cua chinh dot do" {
        ($scanContent -cmatch '(?m)^def flash_evidence\(') -and
        # Khong co banner thi flash_src phai RONG - cam mac dinh co flash sale.
        # Phai dung cho MOI cho goi, khong phai "co it nhat mot cho dung": truoc day khang dinh
        # nay chi doi mot cho khop, nen bo `if banner else []` o nhanh kia van PASS.
        ((([regex]::Matches($scanContent, 'res\["flash_src"\]\s*=\s*flash_evidence\(')).Count) -ge 2) -and
        ((([regex]::Matches($scanContent, 'res\["flash_src"\]\s*=\s*flash_evidence\(')).Count) -eq
         (([regex]::Matches($scanContent, 'flash_evidence\([^)]*\) if banner else \[\]')).Count)) -and
        ($scanContent -cmatch '"flash_src"') -and
        # Bang chung phai di ra toi latest.js, nguoc lai thi web khong truy nguoc duoc.
        ($scanContent -cmatch '(?s)def write_latest_js\(scan\):.*?"flash_src"') -and
        ((Get-Content "tests/verify_scan.js" -Raw -Encoding UTF8) -cmatch 'FLASH KHONG BANG CHUNG:')
    } "Ket luan flash sale khong kem bang chung flash_src, hoac bang chung khong ra toi latest.js, hoac circuit breaker khong con chot kiem"

    # QUYET DINH CUA NGUOI DUNG 10-11-2026: ten trong hub /flashsale VAN du de tinh la flash
    # sale, va PMH van = khoan "Chon 1 trong". He qua da duoc neu ro truoc khi quyet (A6 Pro
    # 5G 8GB/256GB: PMH = 0 trong khi chenh lech gia la 1.220.000) va nguoi dung chap nhan.
    # Chot nay canh dung quyet dinh do: doi `or` thanh `and`, hoac bo in_hub, la dao nguoc no.
    Assert-Check "Quyet dinh 10-11-2026: hub van tinh la flash sale (khong duoc tu y dao)" {
        # CONSTRAINTS.md viet tieng Viet CO DAU - regex phai bam theo dung ky tu that,
        # dung viet khong dau roi tuong la khop (chinh toi vua mac loi do o day).
        $cText = Get-Content "CONSTRAINTS.md" -Raw -Encoding UTF8
        ($cText -cmatch '10-11-2026') -and
        ($cText -cmatch 'is_true_flash') -and
        ($cText -cmatch 'has_quota or in_hub') -and
        # Code phai con dung phep `or`, o ca hai nhanh parse.
        (([regex]::Matches($scanContent, 'is_true_flash = bool\(has_quota or in_hub\)')).Count -ge 2) -and
        ($scanContent -notmatch 'is_true_flash\s*=\s*bool\(has_quota and in_hub\)')
    } "Da dao nguoc quyet dinh 10-11-2026 cua nguoi dung ve flash sale, hoac xoa phan ghi quyet dinh trong CONSTRAINTS.md - day la dinh nghia nghiep vu, phai hoi nguoi dung truoc"

    Assert-Check "Nhan dien flash sale o CA HAI nhanh parse deu phai doi bang chung suat that" {
        # Nhanh parse_next_layout truoc day khong doi suat nao: mot the class chua chu 'orange'
        # hoac 'flash' bat ky trong <main> la du ket luan co flash sale. Trang chi tiet co chu
        # "Den Flash camera sau" trong thong so.
        ($scanContent -cmatch '(?m)^\s+is_true_flash = bool\(has_quota or in_hub\)') -and
        (([regex]::Matches($scanContent, 'is_true_flash = bool\(has_quota or in_hub\)')).Count -ge 2) -and
        (([regex]::Matches($scanContent, 'is_true_flash and \(')).Count -ge 4) -and
        ($scanContent -notmatch 'page\.select_one\("\[class\*=''flash''\]"\)')
    } "Con nhanh nhan dien flash sale khong doi bang chung suat that (has_quota / in_hub)"

    # Loi 10-11-2026: chot "scans.js phai co dot hom nay" khong tru ngay khong phai T2/T6,
    # trong khi write_scans_js CO Y chi giu T2/T6 (quy tac nguoi dung train). Viet chot do vao
    # thu Hai - tinh co la ngay duoc giu nen no PASS. Sang thu Ba no chan lien 3 luot quet tu
    # dong, he thong dung han mot ngay.
    Assert-Check "Chot scans.js phai ton trong KEEP_WEEKDAYS, khong doi dot hom nay vao ngay khac" {
        $cb = Get-Content "tests/verify_scan.js" -Raw -Encoding UTF8
        ($cb -cmatch 'KEEP_WEEKDAYS') -and ($cb -cmatch 'isKeepDay') -and
        ($cb -cmatch '!todayEntry && isKeepDay')
    } "tests/verify_scan.js doi scans.js phai co dot hom nay ke ca ngay khong phai Thu Hai/Thu Sau - mau thuan voi write_scans_js va se chan moi luot quet cac ngay con lai"

    Assert-Check "PDP mat gia do o lan kiem tra cuoi phai de trong gia" {
        ($scanContent -cmatch 'final PDP has no red price') -and
        ($scanContent -cmatch 'mark_unverified\(r,')
    } "PDP mat gia do van co the giu gia cua luot cao truoc"
    Assert-Check "Circuit breaker phai con chot TRANG THAI DONG BANG" {
        $cb = Get-Content "tests/verify_scan.js" -Raw -Encoding UTF8
        ($cb -cmatch 'TRANG THAI DONG BANG:') -and ($cb -cmatch 'CFG\.maxFrozenScans') -and
        ($cb -cmatch 'known-frozen-status')
    } "tests/verify_scan.js mat chot trang thai dong bang - day la thu duy nhat bat duoc dong non-active bi ghim cung gia tri qua nhieu dot"

    # Dev chay tren Windows khong co Python nen khong bien dich duoc scraper truoc khi day len.
    # Workflow verify-python.yml la CHO DUY NHAT scan_tgdd.py thuc su duoc Python doc.
    # Neu no bi xoa thi loi cu phap se chi lo ra luc dot quet 09:00 chay - mat tron mot ngay du lieu.
    Assert-Check "Phai con workflow bien dich Python that (verify-python.yml)" {
        $p = ".github/workflows/verify-python.yml"
        if (-not (Test-Path $p)) { return $false }
        $w = Get-Content $p -Raw -Encoding UTF8
        ($w -cmatch 'compileall') -and ($w -cmatch 'ast\.parse') -and
        ($w -cmatch 'setup-python') -and ($w -match "paths:") -and ($w -cmatch '\*\*\.py')
    } "Mat .github/workflows/verify-python.yml - day la cho duy nhat scraper/*.py duoc Python that bien dich truoc khi dot quet chay"

    # Loi 09-11-2026: circuit breaker chay TRUOC buoc `git rebase -X theirs origin/main`, nen
    # ket qua cua rebase khong bao gio duoc kiem. Rebase tron theo DONG giua hai phien ban cua
    # cung mot dong JSON -> lay "status" cua ban nay va "pmh" cua ban kia -> dong tu mau thuan
    # (status=chua_mo_ban nhung pmh=0) duoc day thang len main.
    Assert-Check "Workflow quet phai chay lai circuit breaker SAU khi rebase, truoc khi push" {
        $w = Get-Content ".github/workflows/scan-tgdd.yml" -Raw -Encoding UTF8
        $afterRebase = $w.Substring($w.IndexOf('git rebase -X theirs'))
        ($afterRebase -cmatch 'node tests/verify_scan\.js') -and ($afterRebase -cmatch 'exit 1')
    } "scan-tgdd.yml khong kiem lai du lieu sau `git rebase -X theirs` - ket qua tron dong cua rebase se duoc push len main ma khong qua check nao"

    Assert-Check "Workflow Python phai con chot AST cam ep cung theo ten model" {
        $w = Get-Content ".github/workflows/verify-python.yml" -Raw -Encoding UTF8
        ($w -cmatch 'ast\.Compare') -and ($w -cmatch 'ast\.In') -and ($w -cmatch 'CONSTRAINTS 2\.9')
    } "verify-python.yml mat chot AST cam khoi `if product[""model""] in (...)` - chot regex trong PowerShell co the lach bang xuong dong, chot AST thi khong"

    Assert-Check "File xac nhan trang thai dong bang phai ton tai va moi muc phai co bang chung" {
        $p = "tests/known-frozen-status.json"
        if (-not (Test-Path $p)) { return $false }
        $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $bad = @($j.entries | Where-Object { -not $_.model -or -not $_.since -or -not $_.rrp -or -not $_.status -or -not $_.reason -or $_.reason.Length -lt 20 })
        $bad.Count -eq 0
    } "tests/known-frozen-status.json co muc thieu model/since/rrp/status hoac `reason` qua so sai - moi xac nhan phai ghi ro bang chung doi soat"

    Assert-Check "CONSTRAINTS.md tuyet doi khong con viet cung so SKU" {
        $cText = Get-Content "CONSTRAINTS.md" -Raw -Encoding UTF8
        $cText -notmatch '\d+\s*SKU\s*Master\s*List' -and $cText -notmatch 'duy tr.{0,3} d.{0,3}\s*\d+\s*SKU'
    } "CONSTRAINTS.md van viet cung mot con so SKU - moi nguong phai doc tu tests/gate-config.json"
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

    Assert-Check "products.csv (danh sach cao) phai co DUNG $($GateCfg.crawlSkuCount) SKU" {
        $csvSku = ((Get-Content "scraper/products.csv") | Where-Object { $_.Trim() }).Count - 1
        $csvSku -eq $GateCfg.crawlSkuCount
    } "products.csv co $(((Get-Content 'scraper/products.csv') | Where-Object { $_.Trim() }).Count - 1) SKU, danh sach cao quy dinh DUNG $($GateCfg.crawlSkuCount) (sua tests/gate-config.json neu day la thay doi co chu y)"

    Assert-Check "scraper/products.csv phai chua day du cac model chuan A7 Pro 5G" {
        $csvText = Get-Content "scraper/products.csv" -Raw -Encoding UTF8
        ($csvText -match 'A7 Pro 5G 6GB/256GB') -and ($csvText -match 'A7 Pro 5G 8GB/128GB') -and ($csvText -match 'A7 Pro 5G 8GB/256GB')
    } "products.csv thieu model bien the A7 Pro 5G"

    Assert-Check "data/links.js phai chua link cho 'A7 Pro 5G 6GB/256GB' va 'A7 Pro 5G 8GB/128GB'" {
        $linksText = Get-Content "data/links.js" -Raw -Encoding UTF8
        ($linksText -match '"A7 Pro 5G 6GB/256GB"') -and ($linksText -match '"A7 Pro 5G 8GB/128GB"')
    } "data/links.js thieu key 'A7 Pro 5G 6GB/256GB' hoac 'A7 Pro 5G 8GB/128GB'"

    Assert-Check "A7 Pro 5G co du bien the va khong lay gia ghim cho du lieu hien tai" {
        $raw = (Get-Content "data/latest.js" -Raw -Encoding UTF8) -replace '^\s*/\*.*?\*/\s*', '' -replace '^\s*window\.LATEST\s*=\s*', ''
        $latestObj = $raw.TrimEnd(" ;`r`n") | ConvertFrom-Json
        $models = @("A7 Pro 5G 6GB/256GB", "A7 Pro 5G 8GB/128GB", "A7 Pro 5G 8GB/256GB")
        @($latestObj.rows | Where-Object { $_.model -in $models }).Count -eq 3 -and
        @($latestObj.rows | Where-Object { $_.model -in $models -and $_.kind -eq "pin" }).Count -eq 0
    } "data/latest.js thieu bien the A7 Pro hoac van dung gia ghim"

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

    Assert-Check "A08 4GB/64GB khong duoc dung gia nham cua bien the khac" {
        $raw = (Get-Content "data/latest.js" -Raw -Encoding UTF8) -replace '^\s*/\*.*?\*/\s*', '' -replace '^\s*window\.LATEST\s*=\s*', ''
        $obj = $raw.TrimEnd(" ;`r`n") | ConvertFrom-Json
        $a08 = $obj.rows | Where-Object { $_.model -eq "A08 4GB/64GB" }
        $a08 -and ($a08.rrp -ne 5590000) -and
        (($a08.status -eq "error" -and $null -eq $a08.pmh) -or
         ($a08.status -eq "active" -and $a08.rrp -eq 4790000))
    } "A08 4GB/64GB bi nham gia bien the hoac chua xac minh ma van hien PMH"

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

    # Ten khang dinh noi ">= 100 dong" va "du T1 den T10" nhung truoc day chi kiem 4 chuoi
    # "T1"/"T4"/"T7"/"T10" co xuat hien o dau do - khong he dem dong, khong he kiem 6 thang
    # con lai. Nay dem that va doi du ca 10 thang.
    Assert-Check "data/data.js: window.RISE_RAW phai dung so dong va dung bo thang da khai trong gate-config" {
        $dtText = Get-Content "data/data.js" -Raw -Encoding UTF8
        if ($dtText -notmatch 'window\.RISE_RAW\s*=\s*\[') { return $false }
        $riseRows = [regex]::Matches($dtText, '\["(T\d+)","[^"]*","([^"]+)"')
        $months = @($riseRows | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $khai = @($GateCfg.riseMonths | Sort-Object -Unique)
        $thieu = @($khai | Where-Object { $months -notcontains $_ })
        $thua = @($months | Where-Object { $khai -notcontains $_ })
        ($riseRows.Count -ge [int]$GateCfg.riseMinRows) -and ($thieu.Count -eq 0) -and ($thua.Count -eq 0)
    } "window.RISE_RAW duoi riseMinRows dong, hoac bo thang khong khop gate-config.riseMonths. Them/bot mot thang phai sua riseMonths trong cung commit - de thay duoc trong diff."

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

    Assert-Check "Tab thi truong khong bu FPT tu file cua luot quet khac" {
        $idxText = Get-Content "index.html" -Raw -Encoding UTF8
        $marketText = Get-Content "scraper/scan_market.py" -Raw -Encoding UTF8
        ($idxText -notmatch 'mkMergeFpt') -and
        ($marketText -notmatch 'FPT lấy từ data/fpt\.js') -and
        ($marketText -notmatch 'fpt_portal_deals\.json')
    } "Tab thi truong van co the dung lai du lieu FPT cua luot quet khac"

    Assert-Check "Tab hien tai an gia khi qua 3 gio hoac thieu timestamp xac minh" {
        $idxText = Get-Content "index.html" -Raw -Encoding UTF8
        ($idxText -match 'MAX_CURRENT_AGE_MS\s*=\s*3\s*\*\s*60') -and
        ($idxText -match 'function isCurrentScan\(') -and
        ($idxText -match 'function applyCurrentAvailability\(') -and
        ($idxText -match 'data-current-unavailable') -and
        ($idxText -match 'Chưa có dữ liệu hiện tại được xác minh')
    } "Tab moi nhat/thi truong co the hien gia qua han nhu du lieu hien tai"

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
    if (-not (Test-Path $tempOut) -or (Get-Item $tempOut).Length -eq 0) {
        Assert-Hard-Fail "Nhom 4 (E2E): Chrome phai xuat duoc DOM" "Chrome khong tao ra DOM trong $tempOut"
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
            # Gio lay tu mot nguon: masterListCount + 1 dong header.
            # Sheet nay khoa theo Master List BAO CAO (data.js), khong phai danh sach cao.
            Assert-Check "E2E: Sheet Lich_Su_Theo_Dot_Quet phai co $($GateCfg.masterListCount) SKU Master List + 1 dong header" {
                $historySheet = $mainFile.sheetsInfo | Where-Object { $_.name -eq "Lich_Su_Theo_Dot_Quet" }
                $historySheet.rowCount -eq ($GateCfg.masterListCount + 1)
            } "Sheet Lich_Su_Theo_Dot_Quet co $(($mainFile.sheetsInfo | Where-Object { $_.name -eq 'Lich_Su_Theo_Dot_Quet' }).rowCount) dong, mong doi $($GateCfg.masterListCount + 1)"

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
        if ((Test-Path $tempDcf) -and (Get-Item $tempDcf).Length -gt 0) {
            $domContent = Get-Content $tempDcf -Raw -Encoding UTF8
            $a7_6_256 = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="A7 Pro 5G 6GB/256GB"[^>]*>(.*?)</tr>')
            $a7_8_128 = [regex]::Match($domContent, '(?s)<tr[^>]*data-m="A7 Pro 5G 8GB/128GB"[^>]*>(.*?)</tr>')
            
            Assert-Check "DOM E2E: $dcf phai render rieng bien the A7 Pro 5G 6GB/256GB" {
                $a7_6_256.Success
            } "$dcf khong render A7 Pro 5G 6GB/256GB"

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

            Assert-Check "DOM E2E: $dcf phai render rieng bien the A7 Pro 5G 8GB/128GB" {
                $a7_8_128.Success
            } "$dcf khong render A7 Pro 5G 8GB/128GB"

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

            # Truoc day khang dinh nay chi kiem HAI ten model ('A5i Pro', 'Honor X7d') - mat 8
            # thang van bao PASS. Nay lay tu chinh RISE_RAW mot model dai dien cho TUNG thang
            # T1..T10 va doi DOM phai render du ca 10.
            Assert-Check "DOM E2E: $dcf phai render day du cac thang lich su tang gia goc T1-T10" {
                $dtText = Get-Content "data/data.js" -Raw -Encoding UTF8
                $daiDien = @{}
                foreach ($m in [regex]::Matches($dtText, '\["(T\d+)","[^"]*","([^"]+)"[^\]]*\]')) {
                    if ($m.Value -match 'FPT Shop') { continue }   # index.html loc bo dong FPT Shop
                    $mo = $m.Groups[1].Value
                    if (-not $daiDien.ContainsKey($mo)) { $daiDien[$mo] = $m.Groups[2].Value }
                }
                $thieu = @($GateCfg.riseMonths | Where-Object {
                    (-not $daiDien.ContainsKey($_)) -or ($domContent -notmatch [regex]::Escape($daiDien[$_]))
                })
                $thieu.Count -eq 0
            } "$dcf bi mat thang lich su tang gia goc (kiem bang model dai dien cua TUNG thang trong gate-config.riseMonths, lay tu chinh RISE_RAW)"

            Assert-Check "DOM E2E: $dcf phai render du 5 model Realme C100/C100x trong tab Lich su tang gia T11" {
                ($domContent -match 'C100x 6GB/128GB') -and
                ($domContent -match 'C100 4G 6GB/128GB') -and
                ($domContent -match 'C100 4G 8GB/128GB') -and
                ($domContent -match 'C100 8GB/256GB') -and
                ($domContent -match 'C100x 4GB/128GB')
            } "$dcf khong render du 5 model Realme C100/C100x tang gia T11"
        } else {
            Assert-Hard-Fail "DOM E2E: $dcf phai xuat duoc DOM" "Chrome khong tao ra DOM cho $dcf"
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

