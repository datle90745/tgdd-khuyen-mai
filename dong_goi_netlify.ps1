[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$zip = Join-Path $root 'deploy_netlify.zip'

Write-Host 'Dang dong goi web cho Netlify...' -ForegroundColor Cyan

if (Test-Path $zip) {
    Remove-Item -Force $zip
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')

try {
    $indexHtml = Join-Path $root 'index.html'
    if (Test-Path $indexHtml) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $indexHtml, 'index.html')
    }

    $dataDir = Join-Path $root 'data'
    if (Test-Path $dataDir) {
        Get-ChildItem -Path $dataDir -File | ForEach-Object {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $_.FullName, ('data/' + $_.Name))
        }
    }
} finally {
    $archive.Dispose()
}

$fileInfo = Get-Item $zip
Write-Host ''
Write-Host '========================================================' -ForegroundColor Green
Write-Host 'THANH CONG! Da tao file: deploy_netlify.zip' -ForegroundColor Green
Write-Host ('Dung luong: {0:N1} KB' -f ($fileInfo.Length / 1KB)) -ForegroundColor Green
Write-Host ('Vi tri: ' + $zip) -ForegroundColor Green
Write-Host 'Chi can keo tha file deploy_netlify.zip vao https://app.netlify.com/drop' -ForegroundColor Yellow
Write-Host '========================================================' -ForegroundColor Green
