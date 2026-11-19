@echo off
title AAU Kurulum Asistani - Yonetici Paneli
chcp 65001 >nul 2>&1

:: Calisma dizinini betigin bulundugu klasore sabitle
cd /d "%~dp0"

REM === Yonetici yetkisi kontrolu - yoksa UAC iste ===
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath 'conhost.exe' -ArgumentList '\"%~f0\" --conhost' -Verb RunAs"
    exit /b 0
)

:: Eger conhost altinda baslatilmadiysa, conhost ile baslat
if "%~1" neq "--conhost" (
    start "" conhost.exe "%~f0" --conhost
    exit /b 0
)

:: Yonetici modunda da konsol boyutunu 90x32 sabitle
mode con: cols=90 lines=32 >nul 2>&1

if not exist "%~dp0src\main.ps1" (
    color 0C
    echo.
    echo [HATA] src\main.ps1 bulunamadi!
    echo Aranan: %~dp0src\main.ps1
    echo.
    pause
    exit /b 1
)

REM === AdminMode parametresi ile baslat ===
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\main.ps1" -AdminMode

set "PS_EXIT=%ERRORLEVEL%"
if %PS_EXIT% neq 0 (
    echo.
    echo [UYARI] Program %PS_EXIT% hata kodu ile sonlandi.
    echo Logs klasorunu inceleyin.
    echo.
    pause
)
exit /b %PS_EXIT%
