$bytes = [System.IO.File]::ReadAllBytes("$PSScriptRoot/../tests/verify-system.ps1")
Write-Host "BOM:" $bytes[0], $bytes[1], $bytes[2]
# If BOM is 239, 187, 191 then it is UTF8 with BOM
