$ErrorActionPreference = "Stop"

$git = "C:\Users\toquo\AppData\Local\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe"

Write-Host "1. Giu nguyen workflow tu origin/main..." -ForegroundColor Cyan
& $git checkout origin/main -- .github/workflows/scan-tgdd.yml

Write-Host "2. Cap nhat commit..." -ForegroundColor Cyan
& $git add -A
& $git commit --amend -m "Cap nhat dong bo 10-Oct: TGDD, CellphoneS, FPT Shop, Viettel Store (440 may)"

Write-Host "3. Dang day len GitHub (push origin main)..." -ForegroundColor Cyan
& $git push origin main

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "THANH CONG! DA DAY DU LIEU LEN GITHUB HOAN TAT!" -ForegroundColor Green
Write-Host "Trang web GitHub Pages se tu dong build lai sau 30 giay tai:" -ForegroundColor Green
Write-Host "https://datle90745.github.io/tgdd-khuyen-mai/" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Green
