$path = "$PSScriptRoot/../promotion tgdd/scraper/scan_market.py"
if (Test-Path $path) {
    $c = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $c = [regex]::Replace($c, 'rows\.append\(row\("[^"]*TGD[^"]*",', 'rows.append(row(TGDD_NAME,')
    $c = [regex]::Replace($c, '"Khuy[^"]*m[^"]*"', 'KM_NAME')
    $c = [regex]::Replace($c, '\("TGD[^"]*",\s*scan_tgdd\)', '(TGDD_NAME, scan_tgdd)')
    if (-not $c.Contains("TGDD_NAME = ")) {
        $c = $c.Replace('KEEP_SCANS = 20', "KEEP_SCANS = 20`nTGDD_NAME = `"TGD\u0110`"`nKM_NAME = `"Khuy\u1ebfn m\u00e3i`"")
    }
    [System.IO.File]::WriteAllText($path, $c, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Updated promotion tgdd/scraper/scan_market.py!"
}
