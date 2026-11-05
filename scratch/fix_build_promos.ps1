$path = "$PSScriptRoot/../build_promos.ps1"
$c = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

$oldPart = @'
$now = Get-Date -Format "dd-MMM HH:mm"
$promosJson = $promos | ConvertTo-Json -Depth 5 -Compress
$target1 = Join-Path $PWD "data\promos.js"
'@

$newPart = @'
$now = Get-Date -Format "dd-MMM HH:mm"
$promosJson = $promos | ConvertTo-Json -Depth 5 -Compress
$fileContent = "/* Tu dong cao uu dai & qua tang kem tu The Gioi Di Dong */`r`n/* Cap nhat: $now */`r`nwindow.PROMOS = $promosJson;`r`n"
$target1 = Join-Path $PWD "data\promos.js"
'@

$c = $c.Replace($oldPart, $newPart)
[System.IO.File]::WriteAllText($path, $c, (New-Object System.Text.UTF8Encoding $true))
Write-Host "Fixed build_promos.ps1!"
