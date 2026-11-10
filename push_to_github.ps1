param([string]$CommitMsg = "Dong bo du lieu $(Get-Date -Format 'dd-MM-yyyy HH:mm')")
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$git = 'C:\Users\toquo\AppData\Local\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe'
if (-not (Test-Path $git)) { $git = 'git' }
function Invoke-Git([string[]]$gitArgs) {
    & $git @gitArgs
    if ($LASTEXITCODE -ne 0) { throw "git $($gitArgs -join ' ') that bai (exit $LASTEXITCODE). Khong day len GitHub." }
}
function Invoke-Gates {
    & node tests/verify_scan.js
    if ($LASTEXITCODE -ne 0) { throw 'Du lieu khong qua circuit breaker; khong day len GitHub.' }
    & powershell -ExecutionPolicy Bypass -File tests/verify-system.ps1
    if ($LASTEXITCODE -ne 0) { throw 'Bo kiem tra he thong that bai; khong day len GitHub.' }
}

Invoke-Gates
Invoke-Git @('add','-A')
& $git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host 'Khong co thay doi can day.'; exit 0 }
if ($LASTEXITCODE -ne 1) { throw 'Khong kiem tra duoc cac file da stage.' }
Invoke-Git @('commit','-m',$CommitMsg)
Invoke-Git @('fetch','origin','main')
Invoke-Git @('rebase','origin/main')
Invoke-Gates
Invoke-Git @('push','origin','main')
Write-Host 'Da day len GitHub thanh cong.'
