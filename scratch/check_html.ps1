$c = [System.IO.File]::ReadAllText("$PSScriptRoot/../promotion tgdd.html", [System.Text.Encoding]::UTF8)
$m = [regex]::Match($c, 'window\.RISE_AUTO\s*=\s*(\[.*?\]);')
if ($m.Success) {
    Write-Host "RISE_AUTO in promotion tgdd.html:"
    Write-Host $m.Groups[1].Value
} else {
    Write-Host "No RISE_AUTO match"
}
