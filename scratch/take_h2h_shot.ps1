$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$indexPath = (Get-Item "$PSScriptRoot/../index.html").FullName
$artifactDir = "C:\Users\toquo\.gemini\antigravity\brain\4201d6fe-7d9c-41aa-9469-7328dab9583e"
$shotPath = Join-Path $artifactDir "shot_h2h_05nov_verified.png"

# We open index.html, click on Market tab, and take a screenshot of the H2H section
# Or screenshot the page with a viewport
cmd /c "`"$chrome`" --headless=old --window-size=1600,2400 --screenshot=`"$shotPath`" `"file:///$indexPath`" 2>nul"

if (Test-Path $shotPath) {
    Write-Host "Screenshot saved to $shotPath"
} else {
    Write-Host "Failed to take screenshot"
}
