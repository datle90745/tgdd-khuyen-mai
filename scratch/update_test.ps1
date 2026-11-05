$path = "$PSScriptRoot/../tests/verify-system.ps1"
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$oldStr = "5\.780\.000|6\.790\.000"
$newStr = "5\.780\.000|5\.790\.000|6\.790\.000|7\.290\.000"
$content = $content.Replace($oldStr, $newStr)
[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding $true))
Write-Host "Updated with UTF8 BOM!"
