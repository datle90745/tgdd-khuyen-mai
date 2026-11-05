$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$out = "$env:TEMP\a17_dump.html"
$htmlPath = (Get-Item "$PSScriptRoot/test_a17_dump.html").FullName
cmd /c "`"$chrome`" --headless=old --dump-dom `"file:///$htmlPath`" 2>nul > `"$out`""
$res = Get-Content $out -Raw -Encoding UTF8
$m = [regex]::Match($res, '(?s)<div id="output">(.*?)</div>')
if ($m.Success) {
    Write-Host $m.Groups[1].Value
} else {
    Write-Host "No match for output div"
}
