$chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$tempOut = "$env:TEMP\verify_a17_h2h.html"
$indexPath = (Get-Item "index.html").FullName
cmd /c "`"$chromePath`" --headless=old --dump-dom `"file:///$indexPath`" 2>nul > `"$tempOut`""

if (Test-Path $tempOut) {
    $dom = Get-Content $tempOut -Raw -Encoding UTF8
    $match = [regex]::Match($dom, '(?s)<tr[^>]*data-m="A17 8GB/128GB"[^>]*>(.*?)</tr>')
    if ($match.Success) {
        Write-Host "Found A17 8GB/128GB row in index.html:"
        Write-Host $match.Groups[1].Value
    } else {
        Write-Host "Could not find A17 8GB/128GB row in latest tab"
    }
}
