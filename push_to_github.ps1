param([string]$CommitMsg = "Dong bo du lieu toan thi truong va FPT Shop $(Get-Date -Format 'dd-MM-yyyy HH:mm')")

$ErrorActionPreference = "Stop"

$git = "C:\Users\toquo\AppData\Local\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe"

Write-Host "1. Fetch commit moi nhat tu origin/main..." -ForegroundColor Cyan
& $git fetch origin main

Write-Host "2. Dong bo commit tu dam may ve may..." -ForegroundColor Cyan
& $git merge origin/main --no-edit 2>$null

Write-Host "3. Chuan bi files..." -ForegroundColor Cyan
& $git add -A

Write-Host "4. Tao commit moi..." -ForegroundColor Cyan
& $git commit -m $CommitMsg 2>$null

Write-Host "5. Dang day len GitHub (push origin main)..." -ForegroundColor Cyan
& $git push origin main

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "THANH CONG! DA CAP NHAT LICH & TINH NANG LEN GITHUB!" -ForegroundColor Green
Write-Host "Trang web GitHub Pages se tu dong build lai sau 30 giay tai:" -ForegroundColor Green
Write-Host "https://datle90745.github.io/tgdd-khuyen-mai/" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
