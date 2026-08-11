@echo off
chcp 65001 >nul
title Gamnina 2000 - проверка репозитория
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Verify-Repository.ps1"
if errorlevel 1 (
  echo.
  echo ПРОВЕРКА НЕ ПРОЙДЕНА. Не нажимай Push origin.
  pause
  exit /b 1
)
echo.
echo Всё правильно: папку можно отправлять на GitHub.
pause

