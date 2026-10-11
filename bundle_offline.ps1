[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$root = "C:\Users\toquo\tgdd-khuyen-mai"
$indexPath = Join-Path $root "index.html"
$xlsxPath = Join-Path $root "xlsx.full.min.js"

$index = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)

if (Test-Path $xlsxPath) {
    $xlsx = [System.IO.File]::ReadAllText($xlsxPath, [System.Text.Encoding]::UTF8)
    $index = $index.Replace('<script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script>', "<script>`r`n/* Embedded SheetJS */`r`n$xlsx`r`n</script>")
}

$dataFiles = @('data.js', 'scans.js', 'latest.js', 'links.js', 'rises.js', 'fpt.js', 'alerts.js', 'market.js', 'promos.js')
foreach ($f in $dataFiles) {
    $p = Join-Path $root ("data\" + $f)
    if (Test-Path $p) {
        $c = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
        $pattern = "(?s)<script src=`"data/$f[^`"]*`"></script>"
        $replacement = "<script>`r`n/* Embedded data/$f */`r`n" + [System.Text.RegularExpressions.Regex]::Escape($c).Replace('\$', '$$') + "`r`n</script>"
        # Using simple string replace where possible
        $m = [regex]::Match($index, $pattern)
        if ($m.Success) {
            $index = $index.Substring(0, $m.Index) + "<script>`r`n/* Embedded data/$f */`r`n" + $c + "`r`n</script>" + $index.Substring($m.Index + $m.Length)
        }
    }
}

$targets = @(
    (Join-Path $root "promotion tgdd.html"),
    (Join-Path $root "promotion tgdd standalone.html"),
    (Join-Path $root "promotion tgdd\promotion tgdd.html")
)

foreach ($t in $targets) {
    [System.IO.File]::WriteAllText($t, $index, [System.Text.Encoding]::UTF8)
    Write-Host "Created: $t ($([math]::Round($index.Length / 1KB, 1)) KB)"
}
