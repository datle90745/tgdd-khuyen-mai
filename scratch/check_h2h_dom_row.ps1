$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$tmpHtml = "$env:TEMP\index_market_tab.html"
$out = "$env:TEMP\dump_market_tab.html"
cmd /c "`"$chrome`" --headless=old --dump-dom `"file:///$tmpHtml`" 2>nul > `"$out`""

$res = Get-Content $out -Raw -Encoding UTF8
$m = [regex]::Match($res, '(?s)<tr[^>]*data-m="A17 8GB/128GB"[^>]*>(.*?)</tr>')
if ($m.Success) {
    Write-Host "H2H row for A17 8GB/128GB:"
    Write-Host $m.Groups[1].Value
} else {
    # Check table rows containing A17
    $matches = [regex]::Matches($res, '(?s)<tr[^>]*>(?:(?!</tr>).)*?A17 8GB/128GB.*?</tr>')
    foreach ($row in $matches) {
        Write-Host "Matched row:"
        Write-Host $row.Value
    }
}
