@echo off
chcp 65001 >nul
echo ========================================================
echo       TỰ ĐỘNG ĐỒNG BỘ & ĐẨY LÊN GITHUB PAGES
echo ========================================================
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0push_to_github.ps1"
echo.
pause
