$path = "$PSScriptRoot/../scraper/scan_market.py"
$c = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

# Replace corrupted literals
$c = [regex]::Replace($c, 'rows\.append\(row\("[^"]*TGD[^"]*",', 'rows.append(row(TGDD_NAME,')
$c = [regex]::Replace($c, '"Khuy[^"]*m[^"]*"', 'KM_NAME')
$c = [regex]::Replace($c, '\("TGD[^"]*",\s*scan_tgdd\)', '(TGDD_NAME, scan_tgdd)')

# Ensure TGDD_NAME and KM_NAME are defined near the top
if (-not $c.Contains("TGDD_NAME = ")) {
    $c = $c.Replace('KEEP_SCANS = 20', "KEEP_SCANS = 20`nTGDD_NAME = `"TGD\u0110`"`nKM_NAME = `"Khuy\u1ebfn m\u00e3i`"")
}

[System.IO.File]::WriteAllText($path, $c, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Updated scraper/scan_market.py!"
