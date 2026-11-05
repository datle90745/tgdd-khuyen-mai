$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$tempOut = "$env:TEMP\h2h_today_out.html"
cmd /c "`"$chromePath`" --headless=old --virtual-time-budget=3000 --dump-dom `"file:///c:/Users/toquo/Documents/antigravity/fervent-raman/scratch/test_h2h_today.html`" 2>nul > `"$tempOut`""
$res = Get-Content $tempOut -Raw -Encoding UTF8
$idx = $res.IndexOf('<pre>')
$end = $res.IndexOf('</pre>')
Write-Host $res.Substring($idx + 5, $end - $idx - 5)
