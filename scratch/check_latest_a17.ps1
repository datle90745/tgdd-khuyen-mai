$raw = [System.IO.File]::ReadAllText("$PSScriptRoot/../data/latest.js", [System.Text.Encoding]::UTF8)
$prefix = "window.LATEST = "
$idx = $raw.IndexOf($prefix)
if ($idx -ge 0) {
    $raw = $raw.Substring($idx + $prefix.Length).Trim()
}
if ($raw.EndsWith(";")) {
    $raw = $raw.Substring(0, $raw.Length - 1).Trim()
}
$data = ConvertFrom-Json $raw
$row = $data.rows | Where-Object { $_.model -like "*A17 8GB*" }
$row | ConvertTo-Json
