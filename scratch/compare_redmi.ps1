$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"

$tempIndex = "$env:TEMP\debug_index.html"
$tempPromo = "$env:TEMP\debug_promo.html"

cmd /c "`"$chromePath`" --headless=old --dump-dom `"file:///c:/Users/toquo/Documents/antigravity/fervent-raman/index.html`" 2>nul > `"$tempIndex`""
cmd /c "`"$chromePath`" --headless=old --dump-dom `"file:///c:/Users/toquo/Documents/antigravity/fervent-raman/promotion tgdd.html`" 2>nul > `"$tempPromo`""

$htmlIndex = Get-Content $tempIndex -Raw -Encoding UTF8
$htmlPromo = Get-Content $tempPromo -Raw -Encoding UTF8

$mIndex = [regex]::Match($htmlIndex, '(?s)<tr[^>]*data-m="Redmi 17 4G 6GB/256GB"[^>]*>(.*?)</tr>')
$mPromo = [regex]::Match($htmlPromo, '(?s)<tr[^>]*data-m="Redmi 17 4G 6GB/256GB"[^>]*>(.*?)</tr>')

Write-Host "=== INDEX.HTML ==="
Write-Host $mIndex.Groups[1].Value

Write-Host "=== PROMOTION TGDD.HTML ==="
Write-Host $mPromo.Groups[1].Value
