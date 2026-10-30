[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$indexPath = Join-Path $root "index.html"
$xlsxPath = Join-Path $root "xlsx.full.min.js"

$index = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)

if (Test-Path $xlsxPath) {
    $bytes = [System.IO.File]::ReadAllBytes($xlsxPath)
    $b64 = [Convert]::ToBase64String($bytes)
    $xlsxPattern = '(?s)<script src="xlsx\.full\.min\.js"></script>\s*<script>if\(!window\.XLSX\).*?<\/script>|<script src="https://cdnjs\.cloudflare\.com/ajax/libs/xlsx/0\.18\.5/xlsx\.full\.min\.js"></script>'
    $index = [regex]::Replace($index, $xlsxPattern, "<script src=`"data:text/javascript;base64,$b64`"></script>")
}

$dataFiles = @('data.js', 'scans.js', 'latest.js', 'links.js', 'rises.js', 'fpt.js', 'alerts.js', 'market.js', 'promos.js')
foreach ($f in $dataFiles) {
    $p = Join-Path $root ("data\" + $f)
    if (Test-Path $p) {
        $c = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
        $pattern = "(?s)<script src=`"data/$f[^`"]*`"></script>"
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

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

foreach ($t in $targets) {
    [System.IO.File]::WriteAllText($t, $index, $utf8NoBom)
    Write-Host "Created: $t ($([math]::Round($index.Length / 1KB, 1)) KB)"
}

# Sync unbundled index.html and xlsx to promotion tgdd/
$subIndex = Join-Path $root "promotion tgdd\index.html"
$rawIndex = [System.IO.File]::ReadAllText($indexPath, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($subIndex, $rawIndex, $utf8NoBom)
Write-Host "Synced: $subIndex"

$subXlsx = Join-Path $root "promotion tgdd\xlsx.full.min.js"
if (Test-Path $xlsxPath) {
    Copy-Item -Path $xlsxPath -Destination $subXlsx -Force
}
