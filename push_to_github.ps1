param([string]$CommitMsg = "Dong bo du lieu toan thi truong va FPT Shop $(Get-Date -Format 'dd-MM-yyyy HH:mm')")

$ErrorActionPreference = "Stop"

$git = "C:\Users\toquo\AppData\Local\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe"
if (!(Test-Path $git)) { $git = "git" }

Write-Host "1. Chuan bi files va commit tai cho..." -ForegroundColor Cyan
& $git add -A
& $git commit -m $CommitMsg 2>$null

Write-Host "2. Fetch commit moi nhat tu origin/main..." -ForegroundColor Cyan
& $git fetch origin main

Write-Host "3. Dong bo commit tu dam may ve may..." -ForegroundColor Cyan
& $git merge origin/main --no-edit 2>$null

Write-Host "4. Dang day len GitHub (push origin main)..." -ForegroundColor Cyan
& $git push origin main

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "THANH CONG! DA CAP NHAT LICH & TINH NANG LEN GITHUB!" -ForegroundColor Green
Write-Host "Trang web GitHub Pages se tu dong build lai sau 30 giay tai:" -ForegroundColor Green
Write-Host "https://datle90745.github.io/tgdd-khuyen-mai/" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
