@echo off
chcp 65001 >nul
echo ========================================================
echo   QUÉT LIVE 4 SÀN VÀ TỰ ĐỘNG ĐẨY LÊN GITHUB PAGES
echo ========================================================
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0sync_all.ps1"
echo.
echo Đang đẩy kết quả mới lên GitHub...
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0push_to_github.ps1"
echo.
pause
