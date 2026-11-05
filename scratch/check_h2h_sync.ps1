$indexPath = (Get-Item "$PSScriptRoot/../index.html").FullName
$tmpHtml = "$env:TEMP\index_h2h_sync.html"
$content = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
$syncRun = @'
<script>
window.addEventListener('DOMContentLoaded', function() {
  renderMarket();
  renderMarketH2H();
});
</script>
</body>
'@
$content = $content.Replace("</body>", $syncRun)
[System.IO.File]::WriteAllText($tmpHtml, $content, [System.Text.Encoding]::UTF8)

$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$out = "$env:TEMP\dump_h2h_sync.html"
cmd /c "`"$chrome`" --headless=old --dump-dom `"file:///$tmpHtml`" 2>nul > `"$out`""

$res = Get-Content $out -Raw -Encoding UTF8
$matches = [regex]::Matches($res, '(?s)<tr[^>]*>(?:(?!</tr>).)*?A17 8GB/128GB.*?</tr>')
Write-Host "Matched rows count:" $matches.Count
foreach ($row in $matches) {
    Write-Host "Row:"
    Write-Host $row.Value
}
