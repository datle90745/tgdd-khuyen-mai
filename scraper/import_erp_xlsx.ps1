# Nạp file Excel xuất từ hệ thống ERP của đồng nghiệp vào tab "Toàn thị trường".
#
# CHỈ dùng cho tab tham khảo. Không dùng để tính KM base (PMH): file của họ không có
# khoản "Chọn 1 trong" và cột "Flash Sale?" của họ không khớp với cách mình nhận diện
# flash sale trên trang TGDĐ, nên không đủ dữ liệu để áp quy tắc KM base của mình.
#
# Dùng:  powershell -File scraper\import_erp_xlsx.ps1 -Xlsx "C:\...\deals_xxx.xlsx"
param(
  [Parameter(Mandatory = $true)][string]$Xlsx,
  [string]$Out = "$PSScriptRoot\..\data\market.js"
)
$ErrorActionPreference = "Stop"

$tmp = Join-Path $env:TEMP ("erp_" + [guid]::NewGuid().ToString("N"))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($Xlsx, $tmp)
try {
  $doc = New-Object System.Xml.XmlDocument
  $doc.Load((Join-Path $tmp "xl\worksheets\sheet1.xml"))
  $ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
  $ns.AddNamespace("d", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")

  function Get-Row($r) {
    $out = New-Object 'string[]' 20
    foreach ($c in $r.SelectNodes("d:c", $ns)) {
      $ref = $c.GetAttribute("r") -replace '\d', ''
      $i = 0; foreach ($ch in $ref.ToCharArray()) { $i = $i * 26 + ([int][char]$ch - 64) }
      $i--
      if ($i -lt 0 -or $i -ge 20) { continue }
      $t = $c.SelectSingleNode("d:is/d:t", $ns)
      if ($t) { $out[$i] = $t.InnerText } else { $v = $c.SelectSingleNode("d:v", $ns); if ($v) { $out[$i] = $v.InnerText } }
    }
    , $out
  }
  function ToInt($s) { $d = ("" + $s) -replace '[^\d]', ''; if ($d) { [int64]$d } else { 0 } }

  $RET = @{ "Thế Giới Di Động" = "TGDĐ"; "CellphoneS" = "CellphoneS"; "FPT Shop" = "FPT Shop"; "Viettel Store" = "Viettel Store" }
  $BRAND = @{ "apple" = "Apple"; "samsung" = "Samsung"; "oppo" = "OPPO"; "xiaomi" = "Xiaomi"; "redmi" = "Xiaomi"; "poco" = "Xiaomi"; "vivo" = "Vivo"; "realme" = "Realme" }

  $xrows = $doc.SelectNodes("//d:sheetData/d:row", $ns)
  $list = New-Object System.Collections.ArrayList
  $scanAt = $null
  for ($i = 1; $i -lt $xrows.Count; $i++) {
    $c = Get-Row $xrows[$i]
    $r = $RET[("" + $c[0]).Trim()]
    if (-not $r) { continue }
    if (("" + $c[1]).Trim() -ne "Điện thoại") { continue }
    $b = $BRAND[("" + $c[2]).ToLower().Trim()]
    if (-not $b) { continue }
    $p = ToInt $c[5]; $o = ToInt $c[9]
    if ($p -le 0) { continue }
    if ($o -lt $p) { $o = $p }
    if (-not $scanAt -and $c[15]) { $scanAt = $c[15] }
    [void]$list.Add([pscustomobject]@{
        r = $r; b = $b; n = ("" + $c[3]).Trim(); u = ("" + $c[13]).Trim(); p = $p; o = $o
        k = $(if (("" + $c[4]) -match "Flash") { "Flash Sale Online" } else { "Khuyến mãi" })
      })
  }

  $when = [datetime]::Now
  if ($scanAt) { [void][datetime]::TryParse($scanAt, [ref]$when) }
  $report = @{}
  foreach ($g in ($list | Group-Object r)) { $report[$g.Name] = $g.Count }

  $scan = [pscustomobject]@{
    date   = $when.ToString("dd-MMM", [Globalization.CultureInfo]::InvariantCulture)
    at     = $when.ToString("HH:mm")
    src    = "erp"
    report = $report
    rows   = $list
  }
  # Giữ lại các đợt cũ để cột "So đợt trước" còn so được, bỏ đợt trùng ngày.
  $scans = New-Object System.Collections.ArrayList
  $outPath = [System.IO.Path]::GetFullPath($Out)
  if (Test-Path $outPath) {
    $old = [System.IO.File]::ReadAllText($outPath, [System.Text.UTF8Encoding]::new($false))
    $s = $old.IndexOf("window.MARKET = ")
    if ($s -ge 0) {
      $e = $old.LastIndexOf(";")
      $prev = $old.Substring($s + 16, $e - $s - 16) | ConvertFrom-Json
      foreach ($x in $prev.scans) { if ($x.date -ne $scan.date) { [void]$scans.Add($x) } }
    }
  }
  [void]$scans.Add($scan)
  while ($scans.Count -gt 8) { $scans.RemoveAt(0) }

  $js = "/* Tự sinh bởi scraper/scan_market.py hoặc scraper/import_erp_xlsx.ps1, đừng sửa tay. */`n" +
        "window.MARKET = " + ([pscustomobject]@{ scans = @($scans) } | ConvertTo-Json -Depth 8 -Compress) + ";`n"
  [System.IO.File]::WriteAllText($outPath, $js, (New-Object System.Text.UTF8Encoding $false))

  "Da nap: ngay=$($scan.date) luc=$($scan.at), $($list.Count) may, $($scans.Count) dot trong file."
  ($list | Group-Object r | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ", "
  ($list | Group-Object b | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ", "
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
