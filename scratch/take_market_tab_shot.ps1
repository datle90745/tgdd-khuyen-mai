$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$indexPath = (Get-Item "$PSScriptRoot/../index.html").FullName
$artifactDir = "C:\Users\toquo\.gemini\antigravity\brain\4201d6fe-7d9c-41aa-9469-7328dab9583e"
$shotPath = Join-Path $artifactDir "shot_market_tab_05nov.png"

$tmpHtml = "$env:TEMP\index_market_tab.html"
$content = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
$autoSwitch = @'
<script>
window.addEventListener('DOMContentLoaded', function() {
  setTimeout(function() {
    var btn = document.querySelector('button[data-tab="market"]');
    if (btn) btn.click();
  }, 400);
});
</script>
</body>
'@
$content = $content.Replace("</body>", $autoSwitch)
[System.IO.File]::WriteAllText($tmpHtml, $content, [System.Text.Encoding]::UTF8)

cmd /c "`"$chrome`" --headless=old --window-size=1600,2800 --screenshot=`"$shotPath`" `"file:///$tmpHtml`" 2>nul"

if (Test-Path $shotPath) {
    Write-Host "Market tab screenshot saved to $shotPath"
}
