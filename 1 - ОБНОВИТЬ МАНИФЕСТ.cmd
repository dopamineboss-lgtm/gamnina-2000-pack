@echo off
chcp 65001 >nul
title Gamnina 2000 - обновление манифеста
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Update-Manifest.ps1"
if errorlevel 1 (
  echo.
  echo ОШИБКА: манифест не обновлён. Ничего не отправляй на GitHub.
  pause
  exit /b 1
)
echo.
echo ГОТОВО. Теперь открой GitHub Desktop, сделай Commit to main и Push origin.
pause

