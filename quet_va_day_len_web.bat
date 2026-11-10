@echo off
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0sync_all.ps1"
if errorlevel 1 (
  echo Dong bo hoac kiem tra that bai. Khong day len GitHub.
  pause
  exit /b 1
)
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0push_to_github.ps1"
if errorlevel 1 (
  echo Day len GitHub that bai. Xem log phia tren.
  pause
  exit /b 1
)
pause
