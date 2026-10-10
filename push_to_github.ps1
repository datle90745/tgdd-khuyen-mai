$ErrorActionPreference = "Stop"

$git = "C:\Users\toquo\AppData\Local\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe"

Write-Host "1. Reset HEAD theo origin/main..." -ForegroundColor Cyan
& $git reset --mixed origin/main

Write-Host "2. Giu nguyen workflow..." -ForegroundColor Cyan
& $git checkout origin/main -- .github/workflows/scan-tgdd.yml

Write-Host "3. Chuan bi files..." -ForegroundColor Cyan
& $git add -A

Write-Host "4. Tao commit moi..." -ForegroundColor Cyan
& $git commit -m "Cap nhat tien ich 1-click bat scripts va dong bo 10-Oct"

Write-Host "5. Dang day len GitHub (push origin main)..." -ForegroundColor Cyan
& $git push origin main

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "THANH CONG! DA DAY DU LIEU LEN GITHUB HOAN TAT!" -ForegroundColor Green
Write-Host "Trang web GitHub Pages se tu dong build lai sau 30 giay tai:" -ForegroundColor Green
Write-Host "https://datle90745.github.io/tgdd-khuyen-mai/" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
