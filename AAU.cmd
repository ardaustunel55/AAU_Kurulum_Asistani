@echo off
setlocal
title AAU Kurulum Asistani
chcp 65001 >nul 2>&1

:: Calisma dizinini betigin bulundugu klasore sabitle
cd /d "%~dp0"

REM === Yonetici yetkisi kontrolu - yoksa UAC iste ===
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath 'conhost.exe' -ArgumentList '\"%~f0\" --conhost' -Verb RunAs"
    exit /b 0
)

:: Eger conhost ile baslatilmadiysa, conhost ile baslat ve bu oturumu sonlandir
if "%~1" neq "--conhost" (
    start "" conhost.exe "%~f0" --conhost
    exit /b 0
)

:: Konsol boyutunu sabitle (90 kolon x 32 satir)
mode con: cols=90 lines=32 >nul 2>&1

:: src\main.ps1 kontrolu
if not exist "%~dp0src\main.ps1" (
    color 0C
    echo.
    echo [HATA] Ana program dosyasi bulunamadi!
    echo Aranan dosya: "%~dp0src\main.ps1"
    echo.
    echo Lutfen proje klasor yapisinin eksiksiz oldugundan emin olun.
    echo.
    echo Pencereyi kapatmak icin herhangi bir tusa basin...
    pause >nul
    exit /b 1
)

:: PowerShell 5.1 ile baslat (Standart Kullanici Paneli)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\main.ps1"

:: Hata durumunda ekranda kal
set "PS_EXIT_CODE=%ERRORLEVEL%"
if %PS_EXIT_CODE% neq 0 (
    echo.
    echo ============================================================================
    echo [UYARI] Program %PS_EXIT_CODE% hata kodu ile sonlandi.
    echo ============================================================================
    echo Ayrintilar icin logs klasorundeki gunluk dosyasini inceleyebilirsiniz.
    echo.
    echo Cikmak icin bir tusa basin...
    pause >nul
)

exit /b %PS_EXIT_CODE%
