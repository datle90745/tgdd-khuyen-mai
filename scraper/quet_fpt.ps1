# Quét FPT Shop từ chính máy của anh/chị.
#
# Máy chủ GitHub bị Cloudflare của FPT khoá sau đúng một trang, nhưng mạng nhà thì vào
# bình thường. Script này tải 6 trang hãng, bóc dữ liệu nhúng sẵn trong HTML và ghi ra
# data/fpt.js để web dùng thay cho phần FPT ít ỏi mà máy chủ lấy được.
#
# Chạy:  powershell -ExecutionPolicy Bypass -File scraper\quet_fpt.ps1
param(
  [string]$Out = "$PSScriptRoot\..\data\fpt.js"
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
$KM_NAME = [regex]::Unescape('Khuy\u1EBFn m\u00E3i')

$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
      "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
$BRAND_PAGES = @("apple-iphone", "samsung", "oppo", "xiaomi", "vivo", "realme")

# Chỉ 6 hãng đang theo dõi. Redmi/POCO tính là Xiaomi.
function Get-Brand($name, $slug) {
  $s = ("$name $slug").ToLower()
  if ($s -match 'iphone|apple')            { return "Apple" }
  if ($s -match 'samsung|galaxy')          { return "Samsung" }
  if ($s -match '\boppo\b')                { return "OPPO" }
  if ($s -match 'xiaomi|redmi|poco')       { return "Xiaomi" }
  if ($s -match '\bvivo\b')                { return "Vivo" }
  if ($s -match 'realme')                  { return "Realme" }
  return $null
}

function Get-Page($slug) {
  for ($i = 1; $i -le 3; $i++) {
    try {
      $r = Invoke-WebRequest "https://fptshop.com.vn/dien-thoai/$slug" -UseBasicParsing -TimeoutSec 60 `
             -Headers @{ 'User-Agent' = $UA; 'Accept-Language' = 'vi-VN,vi;q=0.9' }
      return [System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    } catch {
      Write-Host "  $slug lan $i loi: $($_.Exception.Message)"
      Start-Sleep -Seconds 5
    }
  }
  return ""
}

# Dữ liệu nằm trong khối Next.js nhúng trong HTML, bị escape nên phải bỏ dấu \ trước.
function Read-Items($html) {
  $html = $html.Replace('\"', '"')
  $rawList = New-Object System.Collections.ArrayList
  $seen = New-Object System.Collections.Generic.HashSet[string]
  foreach ($m in [regex]::Matches($html, '"currentPrice":(\d+)')) {
    $from = [Math]::Max(0, $m.Index - 2500)
    $back = $html.Substring($from, $m.Index - $from)
    $slugMatches = [regex]::Matches($back, '"slug":"(dien-thoai/[^"]+)"')
    if ($slugMatches.Count -eq 0) { continue }
    $rawSlug = $slugMatches[$slugMatches.Count - 1].Groups[1].Value
    $baseSlug = $rawSlug.Split('?')[0]
    $skuMatch = [regex]::Match($rawSlug, 'sku=(\d+)')
    $sku = if ($skuMatch.Success) { $skuMatch.Groups[1].Value } else { "" }
    
    $after = $back.Substring($slugMatches[$slugMatches.Count - 1].Index)
    $origs = [regex]::Matches($after, '"originalPrice":(\d+)')
    $before = $back.Substring(0, $slugMatches[$slugMatches.Count - 1].Index)
    $names = [regex]::Matches($before, '"(?:displayName|name)":"([^"]{3,80})"')
    $name = if ($names.Count) { $names[$names.Count - 1].Groups[1].Value } else { $baseSlug }
    $normName = [regex]::Replace($name, '\s+', ' ').Trim()

    $dedupKey = "$baseSlug|$normName"
    if (-not $seen.Add($dedupKey)) { continue }

    $url = if ($sku) { "https://fptshop.com.vn/${baseSlug}?sku=${sku}" } else { "https://fptshop.com.vn/${baseSlug}" }
    [void]$rawList.Add([pscustomobject]@{
        n = $normName
        u = $url
        p = [int64]$m.Groups[1].Value
        o = $(if ($origs.Count) { [int64]$origs[$origs.Count - 1].Groups[1].Value } else { 0 })
        slug = $baseSlug
      })
  }

  $hasCapacity = { param($s) return $s -match '\b(128gb|256gb|512gb|1tb|2tb|64gb|32gb)\b' }
  $slugsWithCap = New-Object System.Collections.Generic.HashSet[string]
  foreach ($it in $rawList) {
    if (& $hasCapacity $it.n) { [void]$slugsWithCap.Add($it.slug) }
  }

  $items = New-Object System.Collections.ArrayList
  foreach ($it in $rawList) {
    if ($slugsWithCap.Contains($it.slug) -and (-not (& $hasCapacity $it.n))) {
      continue
    }
    [void]$items.Add($it)
  }
  return $items
}

$rows = New-Object System.Collections.ArrayList
$seenUrl = New-Object System.Collections.Generic.HashSet[string]
foreach ($slug in $BRAND_PAGES) {
  $html = Get-Page $slug
  if (-not $html) { Write-Host "  $slug : KHONG TAI DUOC"; continue }
  $items = Read-Items $html
  # Bảng giá niêm yết chuẩn để bù giá đen khi FPT ẩn giá gạch (tránh bị hiểu nhầm giá đen tăng)
  $knownRRP = @{}
  $dataJsPath = "$PSScriptRoot\..\data\data.js"
  if (Test-Path $dataJsPath) {
    $dataTxt = [System.IO.File]::ReadAllText($dataJsPath, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($dataTxt, '"model":\s*"([^"]+)",\s*"rrp":\s*(\d+)')) {
      $knownRRP[$m.Groups[1].Value.ToLower().Trim()] = [int64]$m.Groups[2].Value
    }
  }

  $added = 0
  $byModel = [ordered]@{}
  foreach ($it in $items) {
    $b = Get-Brand $it.n $it.u
    if (-not $b -or $it.p -le 0) { continue }

    $o = $it.o
    if ($o -le $it.p) {
      $cleanN = $it.n.ToLower().Replace("samsung", "").Replace("galaxy", "").Replace("apple", "").Replace("iphone", "").Replace("oppo", "").Replace("xiaomi", "").Replace("redmi", "").Replace("poco", "").Replace("vivo", "").Replace("realme", "").Trim()
      foreach ($k in $knownRRP.Keys) {
        $cleanK = $k.Replace("samsung", "").Replace("galaxy", "").Replace("apple", "").Replace("iphone", "").Replace("oppo", "").Replace("xiaomi", "").Replace("redmi", "").Replace("poco", "").Replace("vivo", "").Replace("realme", "").Trim()
        if ($cleanN -eq $cleanK -or ($cleanN -replace '\s+','') -eq ($cleanK -replace '\s+','')) {
          $o = $knownRRP[$k]
          break
        }
      }
      if ($o -lt $it.p) { $o = $it.p }
    }

    $normKey = ("$b|" + $it.n).ToLower()
    $canonicalUrl = $it.u.Split('?')[0]
    $canonicalUrl = [regex]::Replace($canonicalUrl, '-5g-256gb$', '')

    if ($byModel.Contains($normKey)) {
      $cur = $byModel[$normKey]
      if ($o -gt $cur.o -or ($o -eq $cur.o -and $canonicalUrl.Length -lt $cur.u.Length)) {
        $byModel[$normKey] = [pscustomobject]@{
          r = "FPT Shop"; b = $b; n = $it.n; u = $canonicalUrl; p = $it.p; o = $o; k = $KM_NAME
        }
      }
    } else {
      $byModel[$normKey] = [pscustomobject]@{
        r = "FPT Shop"; b = $b; n = $it.n; u = $canonicalUrl; p = $it.p; o = $o; k = $KM_NAME
      }
    }
  }

  foreach ($val in $byModel.Values) {
    if ($seenUrl.Add("$($val.u)|$($val.n)")) {
      [void]$rows.Add($val)
      $added++
    }
  }
  Write-Host ("  {0,-14} {1} may" -f $slug, $added)
  Start-Sleep -Seconds 2
}

$now = Get-Date
$data = [pscustomobject]@{
  date = $now.ToString("dd-MMM", [Globalization.CultureInfo]::InvariantCulture)
  at   = $now.ToString("HH:mm")
  rows = $rows
}
$js = "/* Tự sinh bởi scraper/quet_fpt.ps1 chạy trên máy nhà, đừng sửa tay. */`n" +
      "window.FPT_LOCAL = " + ($data | ConvertTo-Json -Depth 6 -Compress) + ";`n"
$outPath = [System.IO.Path]::GetFullPath($Out)
[System.IO.File]::WriteAllText($outPath, $js, (New-Object System.Text.UTF8Encoding $false))

Write-Host ""
Write-Host "Xong: $($rows.Count) may FPT, ghi vao $outPath"
($rows | Group-Object b | Sort-Object Count -Descending | ForEach-Object { "  {0,-10} {1}" -f $_.Name, $_.Count })
