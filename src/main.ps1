<#
.SYNOPSIS
    AAU Kurulum Asistani - Ana Kontrolcu
.DESCRIPTION
    Windows 10/11 icin PowerShell 5.1 uyumlu, 18 standart kategori ve AAU Yonetici Paneli sistem araci.
.PARAMETER AdminMode
    Yonetici Paneli modunu baslatir. Yalnizca AAU_Admin.cmd tarafindan kullanilir.
.NOTES
    Surum      : 2.0.0
    PowerShell : 5.1+
    Guvenlik   : Salt-okunur; kullanici onaysiz islem yapilmaz.
#>
param([switch]$AdminMode)

$WarningPreference     = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$VerbosePreference     = 'SilentlyContinue'
$DebugPreference       = 'SilentlyContinue'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
    $OutputEncoding           = [System.Text.Encoding]::UTF8
} catch {}
Clear-Host

$script:AppName    = "AAU Kurulum Asistani"
$script:AppVersion = "2.0.0"
$script:AppAuthor  = "AAU"
$script:AdminMode  = $AdminMode.IsPresent

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot }
             elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
             else { (Get-Location).Path }

$parentDir = Split-Path -Parent $scriptDir
if (-not $parentDir -or -not (Test-Path -Path $parentDir)) { $parentDir = (Get-Location).Path }

$script:ProjectRoot   = (Resolve-Path $parentDir).Path
$script:LogsDir       = Join-Path $script:ProjectRoot "logs"
$script:ModulesDir    = Join-Path $script:ProjectRoot "modules"
$script:DataDir       = Join-Path $script:ProjectRoot "data"
$script:ConfigDir     = Join-Path $script:ProjectRoot "config"
$script:AssetsDir     = Join-Path $script:ProjectRoot "assets"
$script:LogoIcoPath      = Join-Path $script:AssetsDir "aau.ico"
if (-not (Test-Path $script:LogoIcoPath)) { $script:LogoIcoPath = Join-Path $script:AssetsDir "logo.ico" }
$script:AdminLogoIcoPath = Join-Path $script:AssetsDir "admin.ico"
$script:LogoPngPath      = Join-Path $script:AssetsDir "logo.png"
$script:LogFilePath   = $null
$script:IsAdmin       = $false
$script:OSName        = "Bilinmeyen Windows Surumu"
$script:OSArch        = "64-bit"
$script:LoadedModules = @()

function Test-IsAdmin {
    try {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-SystemInfoSummary {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $script:OSName = $os.Caption.Trim(); $script:OSArch = $os.OSArchitecture
    } catch {
        try {
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            $script:OSName = $os.Caption.Trim(); $script:OSArch = $os.OSArchitecture
        } catch { $script:OSName = [System.Environment]::OSVersion.VersionString }
    }
}

function Initialize-Logger {
    try {
        if (-not (Test-Path $script:LogsDir)) { $null = New-Item $script:LogsDir -ItemType Directory -Force }
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $script:LogFilePath = Join-Path $script:LogsDir "AAU_$ts.log"
        $global:LogFilePath = $script:LogFilePath
        $global:ProjectRoot = $script:ProjectRoot
        $h = "="*80 + "`n$script:AppName - Islem Gunlugu`nBaslangic: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`nSurum: $script:AppVersion | OS: $script:OSName | PS: $($PSVersionTable.PSVersion)`n" + "="*80
        Set-Content $script:LogFilePath $h -Encoding UTF8
        Write-LogSuccess "Loglama baslatildi."
    } catch { Write-Host "[UYARI] Log olusturulamadi." -ForegroundColor DarkCyan }
}

function global:Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS")][string]$Level="INFO")
    try {
        $p = if ($global:LogFilePath) { $global:LogFilePath } else { $script:LogFilePath }
        if ($p -and (Test-Path $p)) {
            Add-Content $p "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch {}
}
function global:Write-LogInfo    { param([string]$m) global:Write-Log $m "INFO"    }
function global:Write-LogWarn    { param([string]$m) global:Write-Log $m "WARN"    }
function global:Write-LogError   { param([string]$m) global:Write-Log $m "ERROR"   }
function global:Write-LogSuccess { param([string]$m) global:Write-Log $m "SUCCESS" }

function Get-AppSettings {
    $settingsFile = Join-Path $script:ConfigDir "settings.json"
    $defaultSettings = [PSCustomObject]@{
        logging = [PSCustomObject]@{
            max_log_files      = 20
            log_retention_days = 14
        }
    }
    if (Test-Path $settingsFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($settingsFile, [System.Text.Encoding]::UTF8)
            $parsed = ConvertFrom-Json $raw
            if ($parsed) { return $parsed }
        } catch {}
    }
    return $defaultSettings
}

function Invoke-AutoLogCleanup {
    try {
        if (-not $script:LogsDir -or -not (Test-Path $script:LogsDir)) { return }
        $settings = Get-AppSettings
        $maxFiles = 20
        $retentionDays = 14
        try {
            if ($settings.logging.max_log_files) { $maxFiles = [int]$settings.logging.max_log_files }
            if ($settings.logging.log_retention_days) { $retentionDays = [int]$settings.logging.log_retention_days }
        } catch {}

        $allLogs = Get-ChildItem -Path $script:LogsDir -Filter "*.log" -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -ne $script:LogFilePath }

        if (-not $allLogs -or $allLogs.Count -eq 0) { return }

        $cutoffDate = (Get-Date).AddDays(-$retentionDays)
        $deletedCount = 0

        # 1. Belirlenen gun sinirindan eski olan loglari sil
        $oldLogs = @($allLogs | Where-Object { $_.LastWriteTime -lt $cutoffDate })
        foreach ($f in $oldLogs) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                $deletedCount++
            } catch {}
        }

        # 2. Dosya sayisi limitini uygula (en yeni maxFiles kadarini koru, kalanlari sil)
        $remaining = Get-ChildItem -Path $script:LogsDir -Filter "*.log" -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -ne $script:LogFilePath } |
                     Sort-Object LastWriteTime -Descending

        if ($remaining -and $remaining.Count -ge $maxFiles) {
            $toDelete = @($remaining | Select-Object -Skip ($maxFiles - 1))
            foreach ($f in $toDelete) {
                try {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                    $deletedCount++
                } catch {}
            }
        }

        if ($deletedCount -gt 0) {
            Write-LogInfo "Otomatik log temizligi yapildi: $deletedCount eski log dosyasi silindi (Maks: $maxFiles dosya / $retentionDays gun saklama)."
        }
    } catch {
        Write-LogWarn "Otomatik log temizligi hatasi: $($_.Exception.Message)"
    }
}

function Show-LogCleanupMenu {
    $exitLogMenu = $false
    while (-not $exitLogMenu) {
        Show-ScreenTransition
        Show-AppHeader
        Write-Host ""
        Write-Host "  LOG TEMIZLEME VE BAKIM YONETIMI" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        $logs = @(Get-ChildItem -Path $script:LogsDir -Filter "*.log" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -ne $script:LogFilePath })
        $currentLog = if ($script:LogFilePath) { Get-Item -LiteralPath $script:LogFilePath -ErrorAction SilentlyContinue } else { $null }

        $logCount = if ($logs) { $logs.Count } else { 0 }
        $totalBytes = 0
        if ($logs -and $logs.Count -gt 0) {
            $totalBytes = ($logs | Measure-Object -Property Length -Sum).Sum
        }

        $formattedSize = if ($totalBytes -ge 1MB) { "{0:N2} MB" -f ($totalBytes / 1MB) }
                         elseif ($totalBytes -ge 1KB) { "{0:N2} KB" -f ($totalBytes / 1KB) }
                         else { "$totalBytes Byte" }

        Write-Host "  Mevcut Eski Log Sayisi : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$logCount adet" -ForegroundColor White
        Write-Host "  Toplam Kaplanan Alan   : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$formattedSize" -ForegroundColor White
        Write-Host "  Aktif Oturum Logu      : " -ForegroundColor DarkCyan -NoNewline
        if ($currentLog) { Write-Host "$($currentLog.Name) [KORUNUYOR]" -ForegroundColor Green }
        else { Write-Host "Yok" -ForegroundColor Red }

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  [1]  7 gunden eski loglari sil" -ForegroundColor Magenta
        Write-Host "  [2]  14 gunden eski loglari sil" -ForegroundColor Magenta
        Write-Host "  [3]  30 gunden eski loglari sil" -ForegroundColor Magenta
        Write-Host "  [4]  Son 10 log haric tum eski loglari temizle" -ForegroundColor Magenta
        Write-Host "  [5]  Tum eski loglari temizle (Sadece aktif oturum kalsin)" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  [0]  Geri Don" -ForegroundColor Red
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        $inp = Read-MenuInput -Prompt "  Seciminiz [1-5 | 0=Geri]: "
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }

        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitLogMenu = $true
        } elseif ($ch -in "1","2","3","4","5") {
            $targets = @()
            $desc = ""
            switch ($ch) {
                "1" {
                    $cutoff = (Get-Date).AddDays(-7)
                    $targets = @($logs | Where-Object { $_.LastWriteTime -lt $cutoff })
                    $desc = "7 gunden eski loglar"
                }
                "2" {
                    $cutoff = (Get-Date).AddDays(-14)
                    $targets = @($logs | Where-Object { $_.LastWriteTime -lt $cutoff })
                    $desc = "14 gunden eski loglar"
                }
                "3" {
                    $cutoff = (Get-Date).AddDays(-30)
                    $targets = @($logs | Where-Object { $_.LastWriteTime -lt $cutoff })
                    $desc = "30 gunden eski loglar"
                }
                "4" {
                    if ($logs.Count -gt 10) {
                        $sorted = $logs | Sort-Object LastWriteTime -Descending
                        $targets = @($sorted | Select-Object -Skip 10)
                    }
                    $desc = "Son 10 log disindaki eski loglar"
                }
                "5" {
                    $targets = @($logs)
                    $desc = "Tum eski loglar"
                }
            }

            if (-not $targets -or $targets.Count -eq 0) {
                Write-Host ""
                Write-Host "  [BILGI] Belirtilen kritere uyan eski log dosyasi bulunamadi." -ForegroundColor Cyan
                Start-Sleep -Seconds 2
            } else {
                $delCount = 0
                $freedBytes = 0
                foreach ($f in $targets) {
                    try {
                        $freedBytes += $f.Length
                        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                        $delCount++
                    } catch {}
                }
                $freedFmt = if ($freedBytes -ge 1MB) { "{0:N2} MB" -f ($freedBytes / 1MB) }
                            elseif ($freedBytes -ge 1KB) { "{0:N2} KB" -f ($freedBytes / 1KB) }
                            else { "$freedBytes Byte" }

                Write-LogSuccess "Manuel log temizligi yapildi: $delCount dosya silindi ($freedFmt alan acildi) - Kriter: $desc"
                Write-Host ""
                Write-Host "  [BASARILI] $delCount adet log dosyasi basariyla silindi!" -ForegroundColor Green
                Write-Host "  Kazanilan Disk Alani : $freedFmt" -ForegroundColor White
                Start-Sleep -Seconds 2
            }
        } else {
            Write-Host "  [HATA] Gecersiz secim!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

function Initialize-ModuleSystem {
    $script:LoadedModules = @()
    if (-not $script:ModulesDir -or -not (Test-Path $script:ModulesDir)) { Write-LogWarn "modules klasoru yok."; return }
    try {
        $files = Get-ChildItem $script:ModulesDir -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Extension -in ".psm1",".ps1" }
        if ($files -and $files.Count -gt 0) {
            foreach ($f in $files) {
                try {
                    if ($f.Extension -eq ".psm1") { Import-Module $f.FullName -Force -Global -WarningAction SilentlyContinue 2>$null }
                    else {
                        $code = [System.IO.File]::ReadAllText($f.FullName,[System.Text.Encoding]::UTF8)
                        $null = New-Module -Name ([System.IO.Path]::GetFileNameWithoutExtension($f.Name)) -ScriptBlock ([ScriptBlock]::Create($code)) | Import-Module -Global -Force -WarningAction SilentlyContinue 2>$null
                    }
                    $script:LoadedModules += $f.Name
                    Write-LogSuccess "Modul yuklendi: $($f.Name)"
                } catch { Write-LogError "Modul hatasi: $($f.Name) - $($_.Exception.Message)" }
            }
        } else { Write-LogInfo "Yuklenecek modul yok (altyapi hazir)." }
    } catch { Write-LogError "Modul tarama hatasi: $($_.Exception.Message)" }
}

function Set-ConsoleThemePalette {
    # Kullanici tarafindan tanimlanan ozel HEX renk paletini uygular:
    # Kurulum & Yonetim       : #00FF00 (Green)
    # Sistem & Ag Araclari    : #FF9500 (Cyan slot -> Canli Turuncu)
    # Bakim & Ayarlar         : #BD93F9 (Magenta slot -> Canli Mor / Violet)
    # Cizgiler ve Ayiricilar  : #00AEEF (DarkCyan)
    # Cikis ve Uyarilar       : #FF4055 (Red)
    # Secim Istemi (Prompt)   : #00F5D4 (Yellow slot -> Neon Mint Aqua)
    # Terminal Arka Plani     : #0B0B0B (Black)
    # Yonetici Paneli         : #FF2A85 (DarkMagenta slot -> Neon Cyber Pink)
    # Genel Metinler          : #F8FAFC (White)
    try {
        $sigPalette = @'
using System;
using System.Runtime.InteropServices;

public class ConsolePaletteManager {
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD { public short X; public short Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SMALL_RECT { public short Left; public short Top; public short Right; public short Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct CONSOLE_SCREEN_BUFFER_INFOEX {
        public int cbSize;
        public COORD dwSize;
        public COORD dwCursorPosition;
        public ushort wAttributes;
        public SMALL_RECT srWindow;
        public COORD dwMaximumWindowSize;
        public ushort wPopupAttributes;
        public bool bFullscreenSupported;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
        public uint[] ColorTable;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CONSOLE_FONT_INFO_EX {
        public uint cbSize;
        public uint nFont;
        public short dwFontSizeX;
        public short dwFontSizeY;
        public int FontFamily;
        public uint FontWeight;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string FaceName;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleScreenBufferInfoEx(IntPtr hConsoleOutput, ref CONSOLE_SCREEN_BUFFER_INFOEX csbe);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleScreenBufferInfoEx(IntPtr hConsoleOutput, ref CONSOLE_SCREEN_BUFFER_INFOEX csbe);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFO_EX lpConsoleCurrentFontEx);

    public const uint GENERIC_READ = 0x80000000;
    public const uint GENERIC_WRITE = 0x40000000;
    public const uint FILE_SHARE_READ = 1;
    public const uint FILE_SHARE_WRITE = 2;
    public const uint OPEN_EXISTING = 3;
    public const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

    public static bool ApplyTheme() {
        IntPtr hOut = CreateFile("CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (hOut == IntPtr.Zero || hOut == (IntPtr)(-1)) return false;

        uint mode;
        if (GetConsoleMode(hOut, out mode)) {
            SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }

        // Yazı tipini standart modern Consolas TrueType fontuna zorla
        try {
            CONSOLE_FONT_INFO_EX cfi = new CONSOLE_FONT_INFO_EX();
            cfi.cbSize = (uint)Marshal.SizeOf(typeof(CONSOLE_FONT_INFO_EX));
            cfi.FaceName = "Consolas";
            cfi.dwFontSizeY = 16;
            cfi.FontFamily = 54;
            cfi.FontWeight = 400;
            SetCurrentConsoleFontEx(hOut, false, ref cfi);
        } catch {}

        CONSOLE_SCREEN_BUFFER_INFOEX csbe = new CONSOLE_SCREEN_BUFFER_INFOEX();
        csbe.cbSize = Marshal.SizeOf(typeof(CONSOLE_SCREEN_BUFFER_INFOEX));
        if (GetConsoleScreenBufferInfoEx(hOut, ref csbe)) {
            // COLORREF: 0x00BBGGRR
            csbe.ColorTable[0]  = 0x000B0B0B; // Terminal Arka Plani : #0B0B0B (Black)
            csbe.ColorTable[10] = 0x0000FF00; // Kurulum & Yonetim   : #00FF00 (Green)
            csbe.ColorTable[11] = 0x000095FF; // Sistem & Ag Araclari: #FF9500 (Cyan -> Turuncu)
            csbe.ColorTable[13] = 0x00F993BD; // Bakim & Ayarlar     : #BD93F9 (Magenta -> Mor)
            csbe.ColorTable[3]  = 0x00EFAE00; // Cizgiler & Ayraclar : #00AEEF (DarkCyan -> Mavi)
            csbe.ColorTable[12] = 0x005540FF; // Cikis & Uyarilar    : #FF4055 (Red -> Mercan Kirmizi)
            csbe.ColorTable[14] = 0x00D4F500; // Secim Istemi (Prompt): #00F5D4 (Yellow -> Mint Aqua)
            csbe.ColorTable[15] = 0x00FCFAF8; // Genel Metinler      : #F8FAFC (White -> Net Beyaz)
            csbe.ColorTable[5]  = 0x00852AFF; // Yonetici Paneli     : #FF2A85 (DarkMagenta -> Cyber Pink)
            csbe.srWindow.Right++;
            csbe.srWindow.Bottom++;
            SetConsoleScreenBufferInfoEx(hOut, ref csbe);
        }
        return true;
    }
}
'@
        if (-not ([System.Management.Automation.PSTypeName]'ConsolePaletteManager').Type) {
            Add-Type -TypeDefinition $sigPalette -ErrorAction SilentlyContinue
        }
        [ConsolePaletteManager]::ApplyTheme() | Out-Null
        $host.UI.RawUI.BackgroundColor = [ConsoleColor]::Black
        $host.UI.RawUI.ForegroundColor = [ConsoleColor]::White

        # Konsol tampon yuksekligini pencere boyutuna esitleyerek kaydirmayi (scrollback) tamamen kaldir
        try {
            $rawUI = $host.UI.RawUI
            $winH = $rawUI.WindowSize.Height
            if ($winH -gt 0) {
                $buf = $rawUI.BufferSize
                $buf.Height = $winH
                $rawUI.BufferSize = $buf
            }
        } catch {}
    } catch {}
}

function Set-ConsoleCentered {
    # CMD penceresini aktif monitorde tam merkeze ortalar (PS 5.1 / WinAPI P/Invoke)
    try {
        $sig = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class WinPos {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFO {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern bool   GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")]   public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern bool GetMonitorInfo(IntPtr hMon, ref MONITORINFO mi);
    [DllImport("user32.dll")]   public static extern bool   SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, int wParam, IntPtr lParam);
    [DllImport("user32.dll")]   public static extern bool   IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")]   public static extern bool   ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]   public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);

    public static bool Center(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero) return false;

        // Pencere tam ekransa normal moda dondur
        if (IsZoomed(hwnd)) {
            ShowWindow(hwnd, 9); // SW_RESTORE
            System.Threading.Thread.Sleep(50);
        }

        // Kok pencereyi kontrol et (ConPTY / barindirma durumlarinda)
        IntPtr root = GetAncestor(hwnd, 2); // GA_ROOT
        if (root != IntPtr.Zero && root != hwnd) {
            RECT rr;
            if (GetWindowRect(root, out rr)) {
                if ((rr.Right - rr.Left) > 100) hwnd = root;
            }
        }

        RECT r;
        if (!GetWindowRect(hwnd, out r)) return false;
        int winW = r.Right - r.Left;
        int winH = r.Bottom - r.Top;
        if (winW <= 0 || winH <= 0) return false;

        IntPtr hMon = MonitorFromWindow(hwnd, 1);
        MONITORINFO mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (!GetMonitorInfo(hMon, ref mi)) return false;

        int workW = mi.rcWork.Right - mi.rcWork.Left;
        int workH = mi.rcWork.Bottom - mi.rcWork.Top;
        int x = mi.rcWork.Left + (workW - winW) / 2;
        int y = mi.rcWork.Top + (workH - winH) / 2;
        if (y < mi.rcWork.Top) y = mi.rcWork.Top;
        if (x < mi.rcWork.Left) x = mi.rcWork.Left;

        return SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, 0x0001 | 0x0004 | 0x0040);
    }
}
'@
        if (-not ([System.Management.Automation.PSTypeName]'WinPos').Type) {
            Add-Type -TypeDefinition $sig -ErrorAction Stop
        }
        $hwnd = [WinPos]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [WinPos]::Center($hwnd) | Out-Null
        } else {
            $p = [System.Diagnostics.Process]::GetCurrentProcess()
            if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
                [WinPos]::Center($p.MainWindowHandle) | Out-Null
            }
        }
    } catch {}
}

function Set-ConsoleAppIcon {
    # CMD pencere ve gorev cubugu ikonunu gunceller (AdminMode ise admin.ico, standart ise aau.ico)
    try {
        $targetIco = if ($script:AdminMode -and (Test-Path $script:AdminLogoIcoPath)) {
            $script:AdminLogoIcoPath
        } else {
            $script:LogoIcoPath
        }
        if ($targetIco -and (Test-Path $targetIco)) {
            $hwnd = [WinPos]::GetConsoleWindow()
            if ($hwnd -ne [IntPtr]::Zero) {
                Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
                $icon = New-Object System.Drawing.Icon($targetIco)
                if ($icon -and $icon.Handle -ne [IntPtr]::Zero) {
                    [WinPos]::SendMessage($hwnd, 0x0080, 0, $icon.Handle) | Out-Null # WM_SETICON, ICON_SMALL
                    [WinPos]::SendMessage($hwnd, 0x0080, 1, $icon.Handle) | Out-Null # WM_SETICON, ICON_BIG
                }
            }
        }
    } catch {}
}

function Draw-HorizontalLine {
    param([int]$Width=78,[ConsoleColor]$Color=[ConsoleColor]::DarkCyan,[string]$Char="-")
    Write-Host ([string]::new($Char[0],$Width)) -ForegroundColor $Color
}

function Play-ConfirmationSound {
<#
.SYNOPSIS
    Secim onaylama sesi (kullanici tercihiyle sessize alinmistir).
#>
    param([switch]$IsAdmin)
    # Rahatsiz edici sistem bip sesleri devre disi birakildi
    return
}

function Show-ScreenTransition {
<#
.SYNOPSIS
    Sekmeler arasi yumusak gecis (onay sesi ve hafif bekleme).
.DESCRIPTION
    Grafik animasyon olmadan, sekmeler arasi gecisi yumusatmak icin ekrani temizler,
    onaylama sesi calar, hafif bir bekleme uygular ve tampon yuksekligini ayarlar.
#>
    param([switch]$IsAdmin, [switch]$Scrollable)
    try {
        $adminFlag = if ($PSBoundParameters.ContainsKey('IsAdmin')) { $IsAdmin.IsPresent } else { [bool]$script:AdminMode }
        Clear-Host

        # Secim onaylama sesi
        Play-ConfirmationSound -IsAdmin:$adminFlag

        Start-Sleep -Milliseconds 60

        # Tampon yuksekligini ayarla: Scrollable ise 400 satira genislet (ust metinleri okuyabilmek icin), degilse pencereye kilitle
        try {
            $rawUI = $host.UI.RawUI
            $winH = $rawUI.WindowSize.Height
            if ($winH -gt 0) {
                $buf = $rawUI.BufferSize
                $buf.Height = if ($Scrollable) { [Math]::Max(400, $winH) } else { $winH }
                $rawUI.BufferSize = $buf
            }
            $rawUI.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0)
        } catch {}
    } catch {
        Clear-Host
    }
}

function Wait-UserKeyPress {
    param([string]$PromptMessage="Ana menuye donmek icin bir tusa basin...")
    Write-Host ""; Write-Host "  $PromptMessage" -ForegroundColor DarkCyan
    try {
        $null = [Console]::ReadKey($true)
    } catch {
        try { $null = Read-Host } catch { Start-Sleep -Seconds 1 }
    }
}

function Read-MenuInput {
<#
.SYNOPSIS
    ESC destekli menu girisi okur. ESC basilirsa "ESC" dondurur.
    Karakter karakter okuyarak sayi girisini alir, Enter ile onaylar.
#>
    param([string]$Prompt = "  Seciminiz: ", [ConsoleColor]$PromptColor = [ConsoleColor]::Yellow)
    Write-Host $Prompt -ForegroundColor $PromptColor -NoNewline
    $buffer = ""
    while ($true) {
        try {
            $key = [Console]::ReadKey($true)
        } catch {
            # ReadKey kullanilamazsa Read-Host'a geri don
            $fallback = Read-Host
            if ($null -eq $fallback) { return "ESC" }
            return $fallback.Trim()
        }
        if ($key.Key -eq [ConsoleKey]::Escape) {
            Write-Host "ESC" -ForegroundColor DarkGray
            return "ESC"
        }
        if ($key.Key -eq [ConsoleKey]::Enter) {
            Write-Host ""
            return $buffer.Trim()
        }
        if ($key.Key -eq [ConsoleKey]::Backspace) {
            if ($buffer.Length -gt 0) {
                $buffer = $buffer.Substring(0, $buffer.Length - 1)
                Write-Host "`b `b" -NoNewline
            }
            continue
        }
        $c = $key.KeyChar
        if ($c -and [char]::IsLetterOrDigit($c) -or $c -eq '.' -or $c -eq '-' -or $c -eq '_' -or $c -eq ' ') {
            $buffer += $c
            Write-Host $c -NoNewline
        }
    }
}
function Show-OpeningAnimation {
    param([switch]$IsAdmin)

    try {
        Clear-Host
        try { $host.UI.RawUI.CursorVisible = $false } catch {}
        try { $host.UI.RawUI.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0) } catch {}

        $themeColor   = if ($IsAdmin) { [ConsoleColor]::Magenta } else { [ConsoleColor]::Cyan }
        $accentColor  = if ($IsAdmin) { [ConsoleColor]::DarkMagenta } else { [ConsoleColor]::DarkCyan }
        $titleLine    = if ($IsAdmin) { "Y Ö N E T İ C İ   P A N E L İ" } else { "K U R U L U M   A S İ S T A N I" }
        $protocolLine = "D E F E N D E R   P R O T O K O L Ü"

        $indent = " " * 21
        $boxIndent = " " * 14
        $boxInnerW = 56
        $tPadL = [int][Math]::Floor(($boxInnerW - $titleLine.Length) / 2)
        $tPadR = [Math]::Max(0, ($boxInnerW - $titleLine.Length - $tPadL))
        $pPadL = [int][Math]::Floor(($boxInnerW - $protocolLine.Length) / 2)
        $pPadR = [Math]::Max(0, ($boxInnerW - $protocolLine.Length - $pPadL))

        $logoLines = @(
            "  █████╗        █████╗       ██╗   ██╗  ",
            " ██╔══██╗      ██╔══██╗      ██║   ██║  ",
            " ███████║      ███████║      ██║   ██║  ",
            " ██╔══██║      ██╔══██║      ██║   ██║  ",
            " ██║  ██║  ██╗ ██║  ██║  ██╗ ╚██████╔╝  ",
            " ╚═╝  ╚═╝  ╚═╝ ╚═╝  ╚═╝  ╚═╝  ╚═════╝   "
        )

        Write-Host "`n`n"
        foreach ($line in $logoLines) {
            Write-Host "$indent" -NoNewline
            Write-Host $line -ForegroundColor White
            Start-Sleep -Milliseconds 35
        }

        Write-Host ""
        Write-Host "$boxIndent╔$('═' * $boxInnerW)╗" -ForegroundColor $accentColor
        Write-Host "$boxIndent║" -ForegroundColor $accentColor -NoNewline
        Write-Host ((' ' * $tPadL) + $titleLine + (' ' * $tPadR)) -ForegroundColor $themeColor -NoNewline
        Write-Host "║" -ForegroundColor $accentColor
        Write-Host "$boxIndent║" -ForegroundColor $accentColor -NoNewline
        Write-Host ((' ' * $pPadL) + $protocolLine + (' ' * $pPadR)) -ForegroundColor DarkGray -NoNewline
        Write-Host "║" -ForegroundColor $accentColor
        Write-Host "$boxIndent╚$('═' * $boxInnerW)╝" -ForegroundColor $accentColor
        Write-Host ""

        # Dinamik Yukleme Animasyonu
        $barWidth = 46
        $loadSteps = @(
            @{ Pct = 25;  Msg = "Cekirdek moduller yukleniyor..." },
            @{ Pct = 55;  Msg = "Guvenlik ve yetki protokolleri dogrulaniyor..." },
            @{ Pct = 85;  Msg = "Donanim ve WinGet sistemi hazirlaniyor..." },
            @{ Pct = 100; Msg = "Sistem hazir. Arayuz baslatiliyor..." }
        )

        foreach ($st in $loadSteps) {
            $filled = [int]($barWidth * ($st.Pct / 100))
            $empty  = $barWidth - $filled
            $barStr = ("█" * $filled) + ("░" * $empty)

            Write-Host "`r$indent[$barStr] $($st.Pct)%" -ForegroundColor $themeColor -NoNewline
            Write-Host "`n$boxIndent" -NoNewline
            Write-Host ">> $($st.Msg)".PadRight(58) -ForegroundColor DarkGray -NoNewline
            Start-Sleep -Milliseconds 130

            try {
                $cur = $host.UI.RawUI.CursorPosition
                $cur.Y = [Math]::Max(0, $cur.Y - 1)
                $cur.X = 0
                $host.UI.RawUI.CursorPosition = $cur
            } catch {}
        }

        Start-Sleep -Milliseconds 250
        Clear-Host
    } catch {
        Clear-Host
    } finally {
        try { $host.UI.RawUI.CursorVisible = $true } catch {}
    }
}

function Show-ClosingAnimation {
    param([switch]$IsAdmin)

    try {
        Clear-Host
        try { $host.UI.RawUI.CursorVisible = $false } catch {}
        try { $host.UI.RawUI.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0) } catch {}

        $themeColor   = if ($IsAdmin) { [ConsoleColor]::Magenta } else { [ConsoleColor]::Cyan }
        $accentColor  = if ($IsAdmin) { [ConsoleColor]::DarkMagenta } else { [ConsoleColor]::DarkCyan }
        $titleLine    = if ($IsAdmin) { "Y Ö N E T İ C İ   P A N E L İ" } else { "K U R U L U M   A S İ S T A N I" }
        $closeLine    = "O T U R U M   K A P A N I Y O R"
        $byeLine      = "Guvenlik protokolu saglandi. Gule gule!"

        $indent = " " * 21
        $boxIndent = " " * 14
        $boxInnerW = 56
        $c1L = [int][Math]::Floor(($boxInnerW - $titleLine.Length) / 2); $c1R = [Math]::Max(0, ($boxInnerW - $titleLine.Length - $c1L))
        $c2L = [int][Math]::Floor(($boxInnerW - $closeLine.Length) / 2); $c2R = [Math]::Max(0, ($boxInnerW - $closeLine.Length - $c2L))
        $c3L = [int][Math]::Floor(($boxInnerW - $byeLine.Length) / 2);   $c3R = [Math]::Max(0, ($boxInnerW - $byeLine.Length - $c3L))

        $logoLines = @(
            "  █████╗        █████╗       ██╗   ██╗  ",
            " ██╔══██╗      ██╔══██╗      ██║   ██║  ",
            " ███████║      ███████║      ██║   ██║  ",
            " ██╔══██║      ██╔══██║      ██║   ██║  ",
            " ██║  ██║  ██╗ ██║  ██║  ██╗ ╚██████╔╝  ",
            " ╚═╝  ╚═╝  ╚═╝ ╚═╝  ╚═╝  ╚═╝  ╚═════╝   "
        )

        Write-Host "`n`n"
        foreach ($line in $logoLines) {
            Write-Host "$indent" -NoNewline
            Write-Host $line -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "$boxIndent╔$('═' * $boxInnerW)╗" -ForegroundColor $accentColor
        Write-Host "$boxIndent║" -ForegroundColor $accentColor -NoNewline
        Write-Host ((' ' * $c1L) + $titleLine + (' ' * $c1R)) -ForegroundColor $themeColor -NoNewline
        Write-Host "║" -ForegroundColor $accentColor
        Write-Host "$boxIndent║" -ForegroundColor $accentColor -NoNewline
        Write-Host ((' ' * $c2L) + $closeLine + (' ' * $c2R)) -ForegroundColor Yellow -NoNewline
        Write-Host "║" -ForegroundColor $accentColor
        Write-Host "$boxIndent║" -ForegroundColor $accentColor -NoNewline
        Write-Host ((' ' * $c3L) + $byeLine + (' ' * $c3R)) -ForegroundColor White -NoNewline
        Write-Host "║" -ForegroundColor $accentColor
        Write-Host "$boxIndent╚$('═' * $boxInnerW)╝" -ForegroundColor $accentColor
        Write-Host ""

        # Kapanis Cubugu (Geri Sayim / Supurme)
        $barWidth = 46
        for ($pct = 100; $pct -ge 0; $pct -= 20) {
            $filled = [int]($barWidth * ($pct / 100))
            $empty  = $barWidth - $filled
            $barStr = ("█" * $filled) + ("░" * $empty)

            Write-Host "`r$indent[$barStr] Kapanıyor..." -ForegroundColor Yellow -NoNewline
            Start-Sleep -Milliseconds 60
        }

        Start-Sleep -Milliseconds 200
        Clear-Host
    } catch {
        Clear-Host
    } finally {
        try { $host.UI.RawUI.CursorVisible = $true } catch {}
    }
}

function Show-AppBanner {
    param([int]$Indent=10)
    $sp = " " * $Indent
    Write-Host "$sp╔════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "$sp║" -ForegroundColor DarkCyan -NoNewline
    Write-Host "            ███████╗   ███████╗   ██╗   ██╗             " -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor DarkCyan
    Write-Host "$sp║" -ForegroundColor DarkCyan -NoNewline
    Write-Host "            ██╔══██║   ██╔══██║   ██║   ██║             " -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor DarkCyan
    Write-Host "$sp║" -ForegroundColor DarkCyan -NoNewline
    Write-Host "            ███████║   ███████║   ██║   ██║             " -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor DarkCyan
    Write-Host "$sp║" -ForegroundColor DarkCyan -NoNewline
    Write-Host "            ██╔══██║   ██╔══██║   ██║   ██║             " -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor DarkCyan
    Write-Host "$sp║" -ForegroundColor DarkCyan -NoNewline
    Write-Host "            ██║  ██║   ██║  ██║   ╚██████╔╝             " -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor DarkCyan
    Write-Host "$sp║" -ForegroundColor DarkCyan -NoNewline
    if ($script:AdminMode) {
        Write-Host "         YONETICI PANELI  - DEFENDER PROTOKOLU          " -ForegroundColor Magenta -NoNewline
    } else {
        Write-Host "         KURULUM ASISTANI - DEFENDER PROTOKOLU          " -ForegroundColor Cyan -NoNewline
    }
    Write-Host "║" -ForegroundColor DarkCyan
    Write-Host "$sp╚════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
}

function Show-AppHeader {
    param([switch]$Scrollable)
    Clear-Host
    try { $host.UI.RawUI.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0) } catch {}
    # Tampon yuksekligini ayarla: Icerik/rapor ekranlari icin kaydirmayi ac, sabit menuler icin kilitle
    try {
        $rawUI = $host.UI.RawUI
        $winH = $rawUI.WindowSize.Height
        if ($winH -gt 0) {
            $buf = $rawUI.BufferSize
            $buf.Height = if ($Scrollable) { [Math]::Max(400, $winH) } else { $winH }
            $rawUI.BufferSize = $buf
        }
    } catch {}
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "="
    Write-Host "  USER: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($env:USERNAME)" -ForegroundColor White -NoNewline
    Write-Host "  |  PC: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($env:COMPUTERNAME)" -ForegroundColor White -NoNewline
    Write-Host "  |  PS: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" -ForegroundColor White -NoNewline
    Write-Host "  |  ARCH: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$script:OSArch" -ForegroundColor White -NoNewline
    Write-Host "  |  YETKI: " -ForegroundColor DarkCyan -NoNewline
    if ($script:AdminMode) {
        Write-Host "[YONETICI]" -ForegroundColor Green
    } elseif ($script:IsAdmin) {
        Write-Host "[STANDART (ELEVATED)]" -ForegroundColor Green
    } else {
        Write-Host "[STANDART]" -ForegroundColor Cyan
    }
    Write-Host "  CURRENT OS: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$script:OSName" -ForegroundColor White -NoNewline
    Write-Host "  |  SURUM: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "v$script:AppVersion" -ForegroundColor Green -NoNewline
    Write-Host "  |  DEFENDER PROTOKOLU" -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "="
}

function Show-MainMenu {
    Show-ScreenTransition
    Clear-Host
    try { $host.UI.RawUI.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0) } catch {}
    # Tampon yuksekligini pencere boyutuna esitleyerek kaydirma cubugunu kaldir
    try {
        $rawUI = $host.UI.RawUI
        $winH = $rawUI.WindowSize.Height
        if ($winH -gt 0) {
            $buf = $rawUI.BufferSize
            $buf.Height = $winH
            $rawUI.BufferSize = $buf
        }
    } catch {}
    Show-AppBanner -Indent 14
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "="
    Write-Host "  USER: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($env:USERNAME)" -ForegroundColor White -NoNewline
    Write-Host "  |  PC: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($env:COMPUTERNAME)" -ForegroundColor White -NoNewline
    Write-Host "  |  PS: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" -ForegroundColor White -NoNewline
    Write-Host "  |  ARCH: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$script:OSArch" -ForegroundColor White -NoNewline
    Write-Host "  |  YETKI: " -ForegroundColor DarkCyan -NoNewline
    if ($script:IsAdmin) {
        Write-Host "[YONETICI (ELEVATED)]" -ForegroundColor Green
    } else {
        Write-Host "[STANDART]" -ForegroundColor Cyan
    }
    Write-Host "  CURRENT OS: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$script:OSName" -ForegroundColor White -NoNewline
    Write-Host "  |  SURUM: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "v$script:AppVersion" -ForegroundColor Green -NoNewline
    Write-Host "  |  DEFENDER PROTOKOLU" -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "="
    Write-Host "  KULLANICI PANELI - KATEGORI VE ARAC SECIMI" -ForegroundColor White
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

    # 3 Sutun Basliklari
    Write-Host "  " -NoNewline
    Write-Host ("KURULUM & SISTEM".PadRight(29)) -ForegroundColor Green -NoNewline
    Write-Host "  " -NoNewline
    Write-Host ("ARACLAR & AG".PadRight(27)) -ForegroundColor Cyan -NoNewline
    Write-Host "  " -NoNewline
    Write-Host "ONARIM & AYARLAR" -ForegroundColor Magenta
    Write-Host ("  " + ("-"*27) + "  " + ("-"*25) + "  " + ("-"*24)) -ForegroundColor DarkCyan

    # Satir 1
    Write-Host "  " -NoNewline
    Write-Host ("[ 1] | Uygulama Kurulum".PadRight(29)) -ForegroundColor Green -NoNewline
    Write-Host "  " -NoNewline
    Write-Host ("[ 7] | Hizli Araclar".PadRight(27)) -ForegroundColor Cyan -NoNewline
    Write-Host "  " -NoNewline
    Write-Host "[13] | Kullanici Yonetimi" -ForegroundColor Magenta
    # Satir 2
    Write-Host "  " -NoNewline
    Write-Host ("[ 2] | Program Yonetimi".PadRight(29)) -ForegroundColor Green -NoNewline
    Write-Host "  " -NoNewline
    Write-Host ("[ 8] | Ag Araclari".PadRight(27)) -ForegroundColor Cyan -NoNewline
    Write-Host "  " -NoNewline
    Write-Host "[14] | Tani ve Onarim" -ForegroundColor Magenta
    # Satir 3
    Write-Host "  " -NoNewline
    Write-Host ("[ 3] | Windows Yonetimi".PadRight(29)) -ForegroundColor Green -NoNewline
    Write-Host "  " -NoNewline
    Write-Host ("[ 9] | Surucu Yonetimi".PadRight(27)) -ForegroundColor Cyan -NoNewline
    Write-Host "  " -NoNewline
    Write-Host "[15] | Depolama Yonetimi" -ForegroundColor Magenta
    # Satir 4
    Write-Host "  " -NoNewline
    Write-Host ("[ 4] | Donanim & Sistem".PadRight(29)) -ForegroundColor Green -NoNewline
    Write-Host "  " -NoNewline
    Write-Host ("[10] | Yedekleme & Kurtarma".PadRight(27)) -ForegroundColor Cyan -NoNewline
    Write-Host "  " -NoNewline
    Write-Host "[16] | Kisisellestirme" -ForegroundColor Magenta
    # Satir 5
    Write-Host "  " -NoNewline
    Write-Host ("[ 5] | Sistem Temizligi".PadRight(29)) -ForegroundColor Green -NoNewline
    Write-Host "  " -NoNewline
    Write-Host ("[11] | Guvenlik Merkezi".PadRight(27)) -ForegroundColor Cyan -NoNewline
    Write-Host "  " -NoNewline
    Write-Host "[17] | Islem Gecmisi" -ForegroundColor Magenta
    # Satir 6
    Write-Host "  " -NoNewline
    Write-Host ("[ 6] | Sistem Guncellemeleri".PadRight(29)) -ForegroundColor Green -NoNewline
    Write-Host "  " -NoNewline
    Write-Host ("[12] | Performans Optimiz.".PadRight(27)) -ForegroundColor Cyan -NoNewline
    Write-Host "  " -NoNewline
    Write-Host "[18] | Ayarlar" -ForegroundColor Magenta
    Write-Host ""
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

    Write-Host "  " -NoNewline
    Write-Host ("[19] | Windows & Office Lisanslama".PadRight(56)) -ForegroundColor Green -NoNewline
    Write-Host "[20] | Hakkinda" -ForegroundColor Yellow
    Write-Host "  " -NoNewline
    Write-Host ("[21] | Format Sonrasi Sihirbazi".PadRight(56)) -ForegroundColor Cyan -NoNewline
    Write-Host "[22] | Debloat & Gizlilik" -ForegroundColor Yellow
    Write-Host "  " -NoNewline
    Write-Host ("".PadRight(56)) -NoNewline
    Write-Host "[ 0] | Cikis  [ESC]" -ForegroundColor Red
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
}

function Show-PlaceholderScreen {
    param(
        [Parameter(Mandatory)][string]$CategoryNumber,
        [Parameter(Mandatory)][string]$CategoryTitle,
        [string]$Description="Bu modul gelisim asamasindadir.",
        [string[]]$PlannedFeatures=@()
    )
    Write-LogInfo "Kategori secildi: [$CategoryNumber] $CategoryTitle"
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable; Write-Host ""
    Write-Host "  KATEGORI: [$CategoryNumber] $CategoryTitle" -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
    Write-Host "  [BILGI]   " -ForegroundColor Cyan -NoNewline
    Write-Host "Bu modul henuz gelisim asamasindadir." -ForegroundColor White
    Write-Host "  [GUVENLIK]" -ForegroundColor Green -NoNewline
    Write-Host " Sisteminizde herhangi bir degisiklik yapilmadi." -ForegroundColor White
    Write-Host ""; Write-Host "  Aciklama: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$Description" -ForegroundColor White; Write-Host ""
    if ($PlannedFeatures -and $PlannedFeatures.Count -gt 0) {
        Write-Host "  Planlanan Ozellikler:" -ForegroundColor Cyan
        foreach ($f in $PlannedFeatures) { Write-Host "    - $f" -ForegroundColor White }
        Write-Host ""
    }
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Wait-UserKeyPress
}

function Show-SubMenu {
    param(
        [Parameter(Mandatory)][string]$CategoryNumber,
        [Parameter(Mandatory)][string]$CategoryTitle,
        [Parameter(Mandatory)][ConsoleColor]$TitleColor,
        [Parameter(Mandatory)][string[]]$MenuItems
    )
    $exitSub = $false
    while (-not $exitSub) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        $cNumInt = 0
        $isNum = [int]::TryParse($CategoryNumber, [ref]$cNumInt)
        $catTag = if ($isNum -and $cNumInt -lt 10) { "[ $CategoryNumber] |" } else { "[$CategoryNumber] |" }
        Write-Host "  $catTag $CategoryTitle" -ForegroundColor $TitleColor
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $MenuItems) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor $TitleColor -NoNewline
            Write-Host " $item" -ForegroundColor $TitleColor
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "00" -or $ch -eq "0") {
            $exitSub = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $MenuItems.Count) {
                $sel = $MenuItems[$idx - 1]
                Write-LogInfo "Alt menu: [$CategoryNumber.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  $catTag $CategoryTitle  >  [$ch] $sel" -ForegroundColor $TitleColor
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
                Write-Host "  [BILGI]    Bu fonksiyon henuz gelisim asamasindadir." -ForegroundColor Cyan
                Write-Host "  [GUVENLIK] Sisteminizde hicbir degisiklik yapilmadi." -ForegroundColor Green
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}

# ============================================================================
# KATEGORI FONKSIYONLARI (01-18)
# ============================================================================

function Invoke-Category01 {
    $catalog = Import-AppCatalog
    Show-AppInstallCenter -Catalog $catalog
}

function Invoke-Category02 {
    Show-ProgramManagementCenter
}
function Invoke-Category03 {
    $cat03Items = @(
        "Windows Surum Bilgileri (winver)",
        "Bilgisayar Yonetimi Konsolu",
        "Yerel Kullanici ve Gruplar (lusrmgr)",
        "Aygit Yoneticisi",
        "Disk Yonetimi",
        "Windows Hizmetleri (services.msc)",
        "Guc Secenekleri (powercfg.cpl)",
        "Gorev Zamanlayici",
        "Windows Ayarlari Ana Ekrani",
        "Gelismis Sistem Ozellikleri (sysdm.cpl)"
    )
    $exitCat03 = $false
    while (-not $exitCat03) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [ 3] | Windows Yonetim Merkezi" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat03Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Green -NoNewline
            Write-Host " $item" -ForegroundColor Green
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat03 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat03Items.Count) {
                $sel = $cat03Items[$idx - 1]
                Write-LogInfo "Kategori 3 secimi: [3.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [ 3] | Windows Yonetim Merkezi  >  [$ch] $sel" -ForegroundColor Green
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1  { Show-WinverCard }
                    2  { Start-QuickToolApp -CommandName "compmgmt.msc" -ToolTitle "Bilgisayar Yonetimi" }
                    3  { Start-QuickToolApp -CommandName "lusrmgr.msc" -ToolTitle "Yerel Kullanicilar ve Gruplar" }
                    4  { Start-QuickToolApp -CommandName "devmgmt.msc" -ToolTitle "Aygit Yoneticisi" }
                    5  { Start-QuickToolApp -CommandName "diskmgmt.msc" -ToolTitle "Disk Yonetimi" }
                    6  { Start-QuickToolApp -CommandName "services.msc" -ToolTitle "Windows Hizmetleri" }
                    7  { Start-QuickToolApp -CommandName "powercfg.cpl" -ToolTitle "Guc Secenekleri" }
                    8  { Start-QuickToolApp -CommandName "taskschd.msc" -ToolTitle "Gorev Zamanlayici" }
                    9  { Start-QuickToolApp -CommandName "ms-settings:" -ToolTitle "Windows Ayarlari" }
                    10 { Start-QuickToolApp -CommandName "sysdm.cpl" -ToolTitle "Sistem Ozellikleri" }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category04 {
    $cat04Items = @(
        "Islemci Bilgileri",
        "RAM Bilgileri",
        "Ekran Karti Bilgileri",
        "Anakart & BIOS Bilgileri",
        "Disk Bilgileri",
        "Windows Bilgileri",
        "Sistem Raporu Olusturma (TXT)"
    )
    $exitCat04 = $false
    while (-not $exitCat04) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [ 4] | Donanim & Sistem Bilgileri" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat04Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Green -NoNewline
            Write-Host " $item" -ForegroundColor Green
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat04 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat04Items.Count) {
                $sel = $cat04Items[$idx - 1]
                Write-LogInfo "Kategori 4 secimi: [4.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [ 4] | Donanim & Sistem Bilgileri  >  [$ch] $sel" -ForegroundColor Green
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1 { Show-CPUInfo }
                    2 { Show-RAMInfo }
                    3 { Show-GPUInfo }
                    4 { Show-MotherboardBIOSInfo }
                    5 { Show-DiskInfo }
                    6 { Show-WindowsInfo }
                    7 { New-SystemReport }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category05 {
    $cat05Items = @(
        "Kullanici Gecici Dosyalari (Temp)",
        "Windows Sistem Temp Klasoru",
        "Geri Donusum Kutusunu Bosalt",
        "Tarayici ve Kucuk Resim Onbellegi",
        "Windows Disk Temizleme Araci (cleanmgr)",
        "Derin Sistem Temizligi (Hepsini Birlestir)"
    )
    $exitCat05 = $false
    while (-not $exitCat05) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [ 5] | Sistem Temizligi" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat05Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Green -NoNewline
            Write-Host " $item" -ForegroundColor Green
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat05 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat05Items.Count) {
                $sel = $cat05Items[$idx - 1]
                Write-LogInfo "Kategori 5 secimi: [5.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [ 5] | Sistem Temizligi  >  [$ch] $sel" -ForegroundColor Green
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1 { Invoke-UserTempCleanup }
                    2 { Invoke-WindowsTempCleanup }
                    3 { Invoke-RecycleBinEmpty }
                    4 { Invoke-BrowserCacheClear }
                    5 { Start-QuickToolApp -CommandName "cleanmgr.exe" -Arguments "/d C:" -ToolTitle "Disk Temizleme Araci" }
                    6 { Invoke-FullDeepCleanup }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category06 {
    $cat06Items = @(
        "Karanlik Mod / Acik Mod Gecisi (Aninda)",
        "Dosya Uzantilarini Goster / Gizle (Aninda)",
        "Gizli Dosya ve Klasorleri Goster / Gizle (Aninda)",
        "Gorev Cubugu Hizalama: Sol / Orta (Win11)",
        "Klasik Sag Tik Menusu: Ac / Kapat (Win11)",
        "Masaustu Duvar Kagidi ve Tema Ayarlari",
        "Gorev Cubugu ve Baslat Menusu Ayarlari",
        "Ekran Cozunurlugu ve Olcek",
        "Ses Ayarlari ve Aygitlar",
        "Tarih, Saat ve Bolge Ayarlari",
        "Masaustu Sistem Ikonlari (Bu Bilgisayar vb.)",
        "Dosya Gezgini Acilisi: Bu Bilgisayar / Hizli Erisim"
    )
    $exitCat06 = $false
    while (-not $exitCat06) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [ 6] | Kisisellestirme Merkezi" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat06Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Green -NoNewline
            Write-Host " $item" -ForegroundColor Green
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat06 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat06Items.Count) {
                $sel = $cat06Items[$idx - 1]
                Write-LogInfo "Kategori 6 secimi: [6.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [ 6] | Kisisellestirme Merkezi  >  [$ch] $sel" -ForegroundColor Green
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1  {
                        Write-Host "`n  Karanlik Mod / Acik Mod Gecisi Yapiliyor..." -ForegroundColor Cyan
                        try {
                            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
                            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
                            $current = (Get-ItemProperty -Path $regPath -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme
                            $newVal = if ($current -eq 1) { 0 } else { 1 }
                            Set-ItemProperty -Path $regPath -Name "AppsUseLightTheme" -Value $newVal -Type DWord -Force
                            Set-ItemProperty -Path $regPath -Name "SystemUsesLightTheme" -Value $newVal -Type DWord -Force
                            $modeName = if ($newVal -eq 0) { "Karanlik Mod (Dark Mode)" } else { "Acik Mod (Light Mode)" }
                            Write-Host "  [BASARILI] Sistem temasi degistirildi: $modeName" -ForegroundColor Green
                        } catch {
                            Write-Host "  [HATA] Tema degistirilemedi: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                    2  {
                        try {
                            $expPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                            $cur = (Get-ItemProperty -Path $expPath -Name "HideFileExt" -ErrorAction SilentlyContinue).HideFileExt
                            $newVal = if ($cur -eq 0) { 1 } else { 0 }
                            Set-ItemProperty -Path $expPath -Name "HideFileExt" -Value $newVal -Type DWord -Force
                            $st = if ($newVal -eq 0) { "GOSTERILIYOR" } else { "GIZLI" }
                            Write-Host "`n  [BASARILI] Bilinen dosya uzantilari artik: $st" -ForegroundColor Green
                        } catch { Write-Host "`n  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    3  {
                        try {
                            $expPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                            $cur = (Get-ItemProperty -Path $expPath -Name "Hidden" -ErrorAction SilentlyContinue).Hidden
                            $newVal = if ($cur -eq 1) { 2 } else { 1 }
                            Set-ItemProperty -Path $expPath -Name "Hidden" -Value $newVal -Type DWord -Force
                            $st = if ($newVal -eq 1) { "GOSTERILIYOR" } else { "GIZLI" }
                            Write-Host "`n  [BASARILI] Gizli dosya ve klasorler artik: $st" -ForegroundColor Green
                        } catch { Write-Host "`n  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    4  {
                        try {
                            $expPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                            $cur = (Get-ItemProperty -Path $expPath -Name "TaskbarAl" -ErrorAction SilentlyContinue).TaskbarAl
                            $newVal = if ($cur -eq 0) { 1 } else { 0 }
                            Set-ItemProperty -Path $expPath -Name "TaskbarAl" -Value $newVal -Type DWord -Force
                            $st = if ($newVal -eq 0) { "SOLA HIZALI" } else { "ORTALI" }
                            Write-Host "`n  [BASARILI] Gorev cubugu hizalamasi: $st" -ForegroundColor Green
                        } catch { Write-Host "`n  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    5  {
                        try {
                            $clsidPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
                            if (Test-Path $clsidPath) {
                                Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force
                                Write-Host "`n  [BASARILI] Modern Windows 11 sag tik menusu geri yuklendi (Explorer yeniden baslatilmali)." -ForegroundColor Green
                            } else {
                                New-Item -Path $clsidPath -Force | Out-Null
                                Set-ItemProperty -Path $clsidPath -Name "(Default)" -Value "" -Force
                                Write-Host "`n  [BASARILI] Klasik Windows 10 sag tik menusu aktif edildi (Explorer yeniden baslatilmali)." -ForegroundColor Green
                            }
                        } catch { Write-Host "`n  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    6  { Start-QuickToolApp -CommandName "ms-settings:personalization-background" -ToolTitle "Masaustu Duvar Kagidi ve Tema" }
                    7  { Start-QuickToolApp -CommandName "ms-settings:taskbar" -ToolTitle "Gorev Cubugu ve Baslat" }
                    8  { Start-QuickToolApp -CommandName "ms-settings:display" -ToolTitle "Ekran Cozunurlugu ve Olcek" }
                    9  { Start-QuickToolApp -CommandName "ms-settings:sound" -ToolTitle "Ses Ayarlari ve Aygitlar" }
                    10 { Start-QuickToolApp -CommandName "ms-settings:dateandtime" -ToolTitle "Tarih, Saat ve Bolge Ayarlari" }
                    11 { Toggle-DesktopSystemIcons }
                    12 { Toggle-ExplorerLaunchToThisPC }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Kisisellestirme menusune donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category07 {
    $cat07Items = @(
        "Gorev Yoneticisi (taskmgr)",
        "Kayit Defteri Duzenleyicisi (regedit)",
        "Hizmetler Paneli (services.msc)",
        "Sistem Bilgisi (msinfo32)",
        "Grup Ilkesi Duzenleyicisi (gpedit.msc)",
        "Aygit Yoneticisi (devmgmt.msc)",
        "Disk Yonetimi (diskmgmt.msc)",
        "Kaynak Izleyici (resmon)",
        "Sistem Yapilandirmasi (msconfig)",
        "DirectX Tani Araci (dxdiag)",
        "Hesap Makinesi",
        "Karakter Haritasi"
    )
    $exitCat07 = $false
    while (-not $exitCat07) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [ 7] | Hizli Araclar" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat07Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Green -NoNewline
            Write-Host " $item" -ForegroundColor Green
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat07 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat07Items.Count) {
                $sel = $cat07Items[$idx - 1]
                Write-LogInfo "Kategori 7 secimi: [7.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [ 7] | Hizli Araclar  >  [$ch] $sel" -ForegroundColor Green
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1  { Start-QuickToolApp -CommandName "taskmgr.exe" -ToolTitle "Gorev Yoneticisi" }
                    2  { Start-QuickToolApp -CommandName "regedit.exe" -ToolTitle "Kayit Defteri Duzenleyicisi" }
                    3  { Start-QuickToolApp -CommandName "services.msc" -ToolTitle "Hizmetler Paneli" }
                    4  { Start-QuickToolApp -CommandName "msinfo32.exe" -ToolTitle "Sistem Bilgisi" }
                    5  { Start-QuickToolApp -CommandName "gpedit.msc" -ToolTitle "Grup Ilkesi Duzenleyicisi" }
                    6  { Start-QuickToolApp -CommandName "devmgmt.msc" -ToolTitle "Aygit Yoneticisi" }
                    7  { Start-QuickToolApp -CommandName "diskmgmt.msc" -ToolTitle "Disk Yonetimi" }
                    8  { Start-QuickToolApp -CommandName "resmon.exe" -ToolTitle "Kaynak Izleyici" }
                    9  { Start-QuickToolApp -CommandName "msconfig.exe" -ToolTitle "Sistem Yapilandirmasi" }
                    10 { Start-QuickToolApp -CommandName "dxdiag.exe" -ToolTitle "DirectX Tani Araci" }
                    11 { Start-QuickToolApp -CommandName "calc.exe" -ToolTitle "Hesap Makinesi" }
                    12 { Start-QuickToolApp -CommandName "charmap.exe" -ToolTitle "Karakter Haritasi" }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category08 {
    $cat08Items = @(
        "Ag Baglantisi Testi (Ping)",
        "IP ve Ag Bagdastirici Bilgileri",
        "DNS Onbellegi Temizleme (flushdns)",
        "Cloudflare DNS Ayarla (1.1.1.1 / 1.0.0.1)",
        "Google DNS Ayarla (8.8.8.8 / 8.8.4.4)",
        "Otomatik DNS'e (DHCP) Geri Don",
        "Ag Bagdastiricisini Yeniden Baslat / Sifirla",
        "Winsock Sifirla ve IP Yenile (release/renew)",
        "Aktif Dinlenen TCP Portlari (netstat)",
        "Hosts Dosyasini Goruntule / Duzenle"
    )
    $exitCat08 = $false
    while (-not $exitCat08) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [ 8] | Ag Araclari" -ForegroundColor Cyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat08Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Cyan -NoNewline
            Write-Host " $item" -ForegroundColor Cyan
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat08 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat08Items.Count) {
                $sel = $cat08Items[$idx - 1]
                Write-LogInfo "Kategori 8 secimi: [8.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [ 8] | Ag Araclari  >  [$ch] $sel" -ForegroundColor Cyan
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1 { Invoke-PingTestTool }
                    2 { Show-NetworkInfoCard }
                    3 { Invoke-DnsFlushTool }
                    4 { Set-QuickDnsProvider -ProviderName "Cloudflare DNS" -DnsServers @("1.1.1.1", "1.0.0.1") }
                    5 { Set-QuickDnsProvider -ProviderName "Google DNS" -DnsServers @("8.8.8.8", "8.8.4.4") }
                    6 { Reset-DnsToDhcp }
                    7 { Invoke-NetworkAdapterRestart }
                    8 {
                        Write-Host "`n  [WINSOCK & IP YENILEME]" -ForegroundColor Cyan
                        if (-not $script:IsAdmin) {
                            Write-Host "  [UYARI] Winsock sifirlama icin yonetici yetkisi gerekir." -ForegroundColor Yellow
                        } else {
                            & netsh winsock reset
                            & ipconfig /release | Out-Null
                            & ipconfig /renew | Out-Null
                            Write-Host "  [BASARILI] Winsock sifirlandi ve IP adresi yenilendi." -ForegroundColor Green
                        }
                    }
                    9 {
                        Write-Host "`n  [AKTIF DINLENEN TCP PORTLARI]" -ForegroundColor Cyan; Write-Host ""
                        try {
                            Get-NetTCPConnection -State Listen -ErrorAction Stop |
                                Sort-Object LocalPort | Select-Object -First 25 LocalAddress, LocalPort, OwningProcess |
                                Format-Table -AutoSize | Out-String | Write-Host -ForegroundColor White
                        } catch {
                            & netstat -ano | Select-String "LISTENING" | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
                        }
                    }
                    10 {
                        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
                        Write-Host "`n  [HOSTS DOSYASI] $hostsPath" -ForegroundColor Cyan
                        Get-Content $hostsPath -ErrorAction SilentlyContinue | Where-Object { $_ -and -not $_.Trim().StartsWith('#') } | ForEach-Object {
                            Write-Host "  $_" -ForegroundColor White
                        }
                        Write-Host ""
                        $openNote = Read-Host "  Not Defteri ile acilsin mi? (E/H)"
                        if ($openNote -and $openNote.Trim().ToUpper() -eq "E") {
                            Start-Process "notepad.exe" -ArgumentList $hostsPath
                        }
                    }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Show-DriverOverviewCard {
    Write-Host "`n  SURUCU GENEL DURUM RAPORU" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    
    Write-Host "  [1/3] Ucuncu Parti (OEM) Suruculer Taraniyor..." -ForegroundColor Yellow
    $oemRaw = pnputil /enum-drivers
    $oemCount = 0
    foreach ($line in $oemRaw) {
        if ($line -match '^Published Name:\s+(oem\d+\.inf)') { $oemCount++ }
    }

    Write-Host "  [2/3] Donanim Aygitlari & Hata Kodlari Taraniyor..." -ForegroundColor Yellow
    $prob = @(Get-CimInstance Win32_PnPEntity -Filter "ConfigManagerErrorCode <> 0" -ErrorAction SilentlyContinue)

    Write-Host "  [3/3] Imzalanmis Sistem Suruculeri Sayiliyor..." -ForegroundColor Yellow
    $signedCount = (Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Measure-Object).Count

    Write-Host ""
    Write-Host "  Toplam Imzali Surucu    : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$signedCount adet" -ForegroundColor White
    Write-Host "  Yuklu Harici (OEM) INF  : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$oemCount paket" -ForegroundColor Green
    Write-Host "  Hatali / Surucusuz Aygit: " -ForegroundColor DarkCyan -NoNewline
    if ($prob.Count -eq 0) {
        Write-Host "0 adet (Tum donanimlar sorunsuz calisiyor)" -ForegroundColor Green
    } else {
        Write-Host "$($prob.Count) adet sorunlu aygit bulundu!" -ForegroundColor Red
    }
}

function Show-DriverProblematicDevices {
    Write-Host "`n  HATALI VE SURUCUSU EKSIK AYGITLAR" -ForegroundColor Yellow
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    
    $prob = @(Get-CimInstance Win32_PnPEntity -Filter "ConfigManagerErrorCode <> 0" -ErrorAction SilentlyContinue)
    if ($prob.Count -eq 0) {
        Write-Host "  [TEMIZ] Sisteminizde eksik veya hatali surucuye sahip aygit bulunamadi." -ForegroundColor Green
        Write-Host "  Tum PnP aygitlari Windows tarafindan taninmis ve calisir durumda." -ForegroundColor White
    } else {
        Write-Host "  Bulunan Sorunlu Aygitlar ($($prob.Count) Adet):" -ForegroundColor Red
        Write-Host ""
        foreach ($d in $prob) {
            Write-Host "  - Aygit: $($d.Name)" -ForegroundColor White
            Write-Host "    Aygit Kimligi: $($d.DeviceID)" -ForegroundColor DarkGray
            Write-Host "    Hata Kodu    : Kod $($d.ConfigManagerErrorCode)" -ForegroundColor Red
        }
    }
}

function Show-DriverListOEM {
    Write-Host "`n  YUKLU UCUNCU PARTI SURUCULER (OEM INF LISTESI)" -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    
    $raw = pnputil /enum-drivers
    $drivers = [System.Collections.Generic.List[PSCustomObject]]::new()
    $current = @{}
    foreach ($line in $raw) {
        if ($line -match '^Published Name:\s+(.+)$') {
            if ($current.Count -gt 0) { $drivers.Add([PSCustomObject]$current) }
            $current = @{ Inf = $matches[1].Trim() }
        } elseif ($line -match '^Provider Name:\s+(.+)$') {
            $current["Provider"] = $matches[1].Trim()
        } elseif ($line -match '^Class Name:\s+(.+)$') {
            $current["Class"] = $matches[1].Trim()
        } elseif ($line -match '^Driver Version:\s+(.+)$') {
            $current["Version"] = $matches[1].Trim()
        }
    }
    if ($current.Count -gt 0) { $drivers.Add([PSCustomObject]$current) }

    Write-Host ("  {0,-12} {1,-20} {2,-20} {3}" -f "INF DOSYASI", "SAGLAYICI", "SINIF", "SURUM") -ForegroundColor Green
    Write-Host ("  " + ("-" * 80)) -ForegroundColor DarkCyan
    
    $showList = @($drivers | Select-Object -First 25)
    foreach ($drv in $showList) {
        $inf = "$($drv.Inf)"
        $prov = if ($drv.Provider.Length -gt 18) { $drv.Provider.Substring(0, 15) + "..." } else { "$($drv.Provider)" }
        $cls = if ($drv.Class.Length -gt 18) { $drv.Class.Substring(0, 15) + "..." } else { "$($drv.Class)" }
        $ver = "$($drv.Version)"
        Write-Host ("  {0,-12} {1,-20} {2,-20} {3}" -f $inf, $prov, $cls, $ver) -ForegroundColor White
    }
    if ($drivers.Count -gt 25) {
        Write-Host "  ... ve $($drivers.Count - 25) ek OEM surucusu daha yuklu." -ForegroundColor Yellow
    }
}

function Invoke-DriverBackupAll {
    Write-Host "`n  SURUCU YEDEKLEME ISLEMI" -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    
    $targetDir = "C:\AAU_Surucu_Yedekleri_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-Host "  Hedef Yedekleme Dizini: $targetDir" -ForegroundColor White
    Write-Host "  Bu islem sisteminizdeki tum 3. parti suruculeri (.inf, .sys, .cat) disa aktarir." -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Yedeklemeyi baslatmak istiyor musunuz? [E/H]: " -ForegroundColor Yellow -NoNewline
    $ans = Read-Host
    if ($ans -in "E", "e", "EVET", "evet", "Y", "y") {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Host "  Yedekleme calistiriliyor (dism /export-driver)... Lutfen bekleyin..." -ForegroundColor Cyan
        
        $p = Start-Process -FilePath "dism.exe" -ArgumentList "/online /export-driver /destination:`"$targetDir`"" -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0) {
            $backedCount = (Get-ChildItem -Path $targetDir -Filter "*.inf" -Recurse).Count
            Write-Host "  [BASARILI] Suruculer basariyla yedeklendi!" -ForegroundColor Green
            Write-Host "  Toplam $backedCount surucu paketi disa aktarildi." -ForegroundColor White
            Write-Host "  Konum: $targetDir" -ForegroundColor Yellow
        } else {
            Write-Host "  [HATA] Surucu yedekleme basarisiz oldu (Hata Kodu: $($p.ExitCode))." -ForegroundColor Red
            Write-Host "  (Bu islem icin Yonetici yetkisi gerekebilir.)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Islem iptal edildi." -ForegroundColor Yellow
    }
}

function Invoke-Category09 {
    $cat09Items = @(
        "Surucu Genel Durumu ve Ozeti",
        "Hatali ve Surucusu Eksik Aygitlar",
        "Yuklu OEM Suruculeri Listele (pnputil)",
        "Aygit Yoneticisi (devmgmt.msc)",
        "Windows Update ile Surucu Guncelleme",
        "Istege Bagli Surucu Guncellemeleri",
        "Sistem Suruculerini Dısa Aktar (Yedekle)",
        "INF Dosyasindan Surucu Ekle / Kur",
        "Surucu Imza Dogrulama Araci (sigverif)",
        "Yazici ve Tarayici Suruculeri (printmanagement)",
        "DirectX Teshis Araci (dxdiag)",
        "Ekran Karti Otomatik Tespiti ve Surucu Sayfasi"
    )
    $exitCat09 = $false
    while (-not $exitCat09) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [ 9] | Surucu Yonetim Merkezi" -ForegroundColor Cyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat09Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Cyan -NoNewline
            Write-Host " $item" -ForegroundColor Cyan
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat09 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat09Items.Count) {
                $sel = $cat09Items[$idx - 1]
                Write-LogInfo "Kategori 9 secimi: [9.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [ 9] | Surucu Yonetim Merkezi  >  [$ch] $sel" -ForegroundColor Cyan
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1  { Show-DriverOverviewCard }
                    2  { Show-DriverProblematicDevices }
                    3  { Show-DriverListOEM }
                    4  { Start-QuickToolApp -CommandName "devmgmt.msc" -ToolTitle "Aygit Yoneticisi" }
                    5  { Start-QuickToolApp -CommandName "ms-settings:windowsupdate" -ToolTitle "Windows Update" }
                    6  { Start-QuickToolApp -CommandName "ms-settings:windowsupdate-optionalupdates" -ToolTitle "Istege Bagli Surucu Guncellemeleri" }
                    7  { Invoke-DriverBackupAll }
                    8  {
                        Write-Host "`n  INF DOSYASINDAN SURUCU YUKLEME (pnputil /add-driver)" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        Write-Host "  Yuklemek istediginiz .INF dosyasinin tam yolunu girin:" -ForegroundColor White
                        Write-Host "  (Orn: C:\Drivers\display.inf)" -ForegroundColor DarkGray
                        Write-Host "  Yol: " -ForegroundColor Yellow -NoNewline
                        $infPath = Read-Host
                        if ($infPath -and (Test-Path $infPath.Trim('"'))) {
                            $cleanInf = $infPath.Trim('"')
                            Write-Host "  Surucu yukleniyor... Lutfen bekleyin..." -ForegroundColor Cyan
                            $res = pnputil /add-driver "$cleanInf" /install
                            $res | Out-String | Write-Host
                        } else {
                            Write-Host "  [HATA] Belirtilen dosya yolu bulunamadi veya gecersiz!" -ForegroundColor Red
                        }
                    }
                    9  { Start-QuickToolApp -CommandName "sigverif.exe" -ToolTitle "Surucu Imza Dogrulama" }
                    10 { Start-QuickToolApp -CommandName "printmanagement.msc" -ToolTitle "Yazici Yonetimi" }
                    11 { Start-QuickToolApp -CommandName "dxdiag.exe" -ToolTitle "DirectX Teshis Araci" }
                    12 { Invoke-GpuAutoDetectDriver }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Surucu menusune donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category10 {
    $cat10Items = @(
        "Geri Yukleme Noktalarini Listele",
        "Sistem Geri Yukleme Noktasi Olustur",
        "Sistemi Geri Yukleme Noktasina Don (rstrui)",
        "Sistem Koruma Ayarlari (System Protection)",
        "Kayit Defteri Yedekleme (HKCU)",
        "Kayit Defteri Geri Yukleme",
        "Windows Yedekleme ve Geri Yukleme (sdclt)",
        "Windows Yedekleme Ayarlari (Yeni)",
        "Dosya Gecmisi (File History)",
        "Kurtarma Secenekleri (Sifirlama / Gelismis Baslangic)",
        "OneDrive / Bulut Yedekleme Durumu",
        "Onemli Klasorlerin Yedegini Al",
        "Wi-Fi Aglari ve Sifrelerini Yedekle / Geri Yukle"
    )
    $exitCat10 = $false
    while (-not $exitCat10) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [10] | Yedekleme ve Kurtarma Merkezi" -ForegroundColor Cyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat10Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Cyan -NoNewline
            Write-Host " $item" -ForegroundColor Cyan
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat10 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat10Items.Count) {
                $sel = $cat10Items[$idx - 1]
                Write-LogInfo "Kategori 10 secimi: [10.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [10] | Yedekleme ve Kurtarma  >  [$ch] $sel" -ForegroundColor Cyan
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1  {
                        # Geri Yukleme Noktalarini Listele
                        Write-Host ""
                        Write-Host "  SISTEM GERI YUKLEME NOKTALARI" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        try {
                            $restorePoints = Get-ComputerRestorePoint -ErrorAction Stop
                            if ($restorePoints -and $restorePoints.Count -gt 0) {
                                Write-Host "  Toplam $($restorePoints.Count) geri yukleme noktasi bulundu:" -ForegroundColor Green
                                Write-Host ""
                                $rpIndex = 1
                                foreach ($rp in ($restorePoints | Sort-Object SequenceNumber -Descending)) {
                                    $rpDate = try { [Management.ManagementDateTimeConverter]::ToDateTime($rp.CreationTime) } catch { $rp.CreationTime }
                                    $rpType = switch ($rp.RestorePointType) { 0 {"Uygulama"} 6 {"Geri Yukleme"} 7 {"Denetim Noktasi"} 10 {"Aygit Surucu"} 12 {"Kurulum"} 13 {"Kaldirma"} default {"Sistem ($($rp.RestorePointType))"} }
                                    $numDisp = if ($rpIndex -lt 10) { "  [ $rpIndex]" } else { "  [$rpIndex]" }
                                    Write-Host "$numDisp " -ForegroundColor Yellow -NoNewline
                                    Write-Host "Sira: $($rp.SequenceNumber) | " -ForegroundColor DarkCyan -NoNewline
                                    Write-Host "$rpDate" -ForegroundColor White -NoNewline
                                    Write-Host " | " -ForegroundColor DarkCyan -NoNewline
                                    Write-Host "$rpType" -ForegroundColor Green -NoNewline
                                    Write-Host " | $($rp.Description)" -ForegroundColor White
                                    $rpIndex++
                                }
                            } else {
                                Write-Host "  [BILGI] Sistemde geri yukleme noktasi bulunamadi." -ForegroundColor Yellow
                                Write-Host "  Sistem Koruma'nin acik oldugundan emin olun." -ForegroundColor DarkGray
                            }
                        } catch {
                            $errMsg = "$($_.Exception.Message)"
                            if ($errMsg -match "Erisim engellendi|Access is denied|yetki|permission|privilege") {
                                Write-Host "  [UYARI] Geri yukleme noktalari icin Yonetici yetkisi gerekiyor." -ForegroundColor Yellow
                                Write-Host "  Uygulamayi Yonetici olarak calistirin veya rstrui.exe ile kontrol edin." -ForegroundColor DarkGray
                            } else {
                                Write-Host "  [UYARI] Geri yukleme noktalari alinamadi: $errMsg" -ForegroundColor Yellow
                                Write-Host "  Sistem Koruma etkin olmayabilir." -ForegroundColor DarkGray
                            }
                        }
                    }
                    2  {
                        # Sistem Geri Yukleme Noktasi Olustur
                        Write-Host ""
                        Write-Host "  YENi GERI YUKLEME NOKTASI OLUSTUR" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        Write-Host "  Geri yukleme noktasi icin bir aciklama girin:" -ForegroundColor White
                        Write-Host "  (Bos birakirsaniz otomatik ad verilir)" -ForegroundColor DarkGray
                        Write-Host "  Aciklama: " -ForegroundColor Yellow -NoNewline
                        $rpDesc = Read-Host
                        if (-not $rpDesc) { $rpDesc = "AAU Kurulum Asistani - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
                        Write-Host ""
                        Write-Host "  Geri yukleme noktasi olusturuluyor..." -ForegroundColor Cyan
                        Write-Host "  Aciklama: $rpDesc" -ForegroundColor White
                        try {
                            Checkpoint-Computer -Description $rpDesc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                            Write-Host "  [BASARILI] Geri yukleme noktasi olusturuldu!" -ForegroundColor Green
                            Write-LogInfo "Geri yukleme noktasi olusturuldu: $rpDesc"
                        } catch {
                            $errMsg = "$($_.Exception.Message)"
                            if ($errMsg -match "Erisim engellendi|Access is denied|yetki|privilege|izin") {
                                Write-Host "  [UYARI] Geri yukleme noktasi olusturmak icin Yonetici yetkisi gerekiyor." -ForegroundColor Yellow
                                Write-Host ""
                                Write-Host "  Sistem Koruma penceresini acarak manuel olusturabilirsiniz." -ForegroundColor DarkGray
                                Write-Host "  Sistem Koruma acilsin mi? (E/H): " -ForegroundColor Yellow -NoNewline
                                $openSP = Read-Host
                                if ($openSP -match "^[Ee]") {
                                    Start-Process "SystemPropertiesProtection.exe" -ErrorAction SilentlyContinue
                                    Write-Host "  [BASARILI] Sistem Koruma penceresi acildi." -ForegroundColor Green
                                }
                            } elseif ($errMsg -match "sikligi|frequency|24 saat|skipped") {
                                Write-Host "  [UYARI] Son 24 saat icinde zaten bir geri yukleme noktasi olusturulmus." -ForegroundColor Yellow
                                Write-Host "  Windows varsayilan olarak 24 saatte bir geri yukleme noktasi olusturulmasina izin verir." -ForegroundColor DarkGray
                            } else {
                                Write-Host "  [HATA] Geri yukleme noktasi olusturulamadi: $errMsg" -ForegroundColor Red
                            }
                        }
                    }
                    3  {
                        # Sistemi Geri Yukleme Noktasina Don (rstrui)
                        Write-Host ""
                        Write-Host "  SISTEM GERI YUKLEME SIHIRBAZI" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        Write-Host "  Windows Sistem Geri Yukleme sihirbazi acilacak." -ForegroundColor White
                        Write-Host "  Buradan mevcut geri yukleme noktalarindan birini secip sisteminizi" -ForegroundColor DarkGray
                        Write-Host "  o tarihe geri dondurebilirsiniz." -ForegroundColor DarkGray
                        Write-Host ""
                        Start-QuickToolApp -CommandName "rstrui.exe" -ToolTitle "Sistem Geri Yukleme Sihirbazi"
                    }
                    4  {
                        # Sistem Koruma Ayarlari
                        Write-Host ""
                        Write-Host "  SISTEM KORUMA AYARLARI" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        Write-Host "  Sistem Ozellikleri > Sistem Koruma sekmesi acilacak." -ForegroundColor White
                        Write-Host "  Buradan:" -ForegroundColor DarkGray
                        Write-Host "    - Suruceler icin koruma'yi ac/kapat" -ForegroundColor DarkGray
                        Write-Host "    - Disk alanini ayarla" -ForegroundColor DarkGray
                        Write-Host "    - Manuel geri yukleme noktasi olustur" -ForegroundColor DarkGray
                        Write-Host ""
                        Start-QuickToolApp -CommandName "SystemPropertiesProtection.exe" -ToolTitle "Sistem Koruma Ayarlari"
                    }
                    5  {
                        # Kayit Defteri Yedekleme (HKCU)
                        Write-Host ""
                        Write-Host "  KAYIT DEFTERI YEDEKLEME (HKCU)" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        $backupDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "AAU_Registry_Yedekleri"
                        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
                        $backupFile = Join-Path $backupDir "HKCU_Yedek_$timestamp.reg"
                        Write-Host "  Kullanici kayit defteri (HKCU) yedekleniyor..." -ForegroundColor White
                        Write-Host "  Hedef: $backupFile" -ForegroundColor DarkGray
                        Write-Host ""
                        try {
                            if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
                            $regProc = Start-Process "reg.exe" -ArgumentList "export HKCU `"$backupFile`" /y" -Wait -NoNewWindow -PassThru -ErrorAction Stop
                            if ($regProc.ExitCode -eq 0 -and (Test-Path $backupFile)) {
                                $fileSize = (Get-Item $backupFile).Length
                                $sizeStr = if ($fileSize -gt 1MB) { "{0:N1} MB" -f ($fileSize / 1MB) } else { "{0:N0} KB" -f ($fileSize / 1KB) }
                                Write-Host "  [BASARILI] HKCU kayit defteri yedeklendi!" -ForegroundColor Green
                                Write-Host "  Dosya: $backupFile" -ForegroundColor White
                                Write-Host "  Boyut: $sizeStr" -ForegroundColor White
                                Write-LogInfo "HKCU yedekleme basarili: $backupFile ($sizeStr)"
                            } else {
                                Write-Host "  [HATA] Yedekleme tamamlanamadi (Cikis kodu: $($regProc.ExitCode))" -ForegroundColor Red
                            }
                        } catch {
                            Write-Host "  [HATA] Kayit defteri yedeklenemedi: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                    6  {
                        # Kayit Defteri Geri Yukleme
                        Write-Host ""
                        Write-Host "  KAYIT DEFTERI GERI YUKLEME" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        $backupDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "AAU_Registry_Yedekleri"
                        if (Test-Path $backupDir) {
                            $regFiles = @(Get-ChildItem -Path $backupDir -Filter "*.reg" -File | Sort-Object LastWriteTime -Descending)
                            if ($regFiles.Count -gt 0) {
                                Write-Host "  Mevcut yedek dosyalari:" -ForegroundColor White
                                Write-Host ""
                                $fi = 1
                                foreach ($rf in $regFiles) {
                                    $sizeStr = if ($rf.Length -gt 1MB) { "{0:N1} MB" -f ($rf.Length / 1MB) } else { "{0:N0} KB" -f ($rf.Length / 1KB) }
                                    $numDisp = if ($fi -lt 10) { "  [ $fi]" } else { "  [$fi]" }
                                    Write-Host "$numDisp " -ForegroundColor Yellow -NoNewline
                                    Write-Host "$($rf.Name)" -ForegroundColor White -NoNewline
                                    Write-Host "  ($sizeStr, $($rf.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor DarkGray
                                    $fi++
                                }
                                Write-Host ""
                                Write-Host "  [UYARI] Kayit defteri geri yuklemesi sistemi etkileyebilir!" -ForegroundColor Yellow
                                Write-Host "  Secilen .reg dosyasi regedit ile acilacaktir." -ForegroundColor DarkGray
                                Write-Host "  Geri yuklenecek dosya numarasi (0 = Iptal): " -ForegroundColor Yellow -NoNewline
                                $selNum = Read-Host
                                if ($selNum -match "^\d+$" -and [int]$selNum -ge 1 -and [int]$selNum -le $regFiles.Count) {
                                    $selFile = $regFiles[[int]$selNum - 1].FullName
                                    Write-Host "  Regedit ile aciliyor: $selFile" -ForegroundColor Cyan
                                    Start-Process "regedit.exe" -ArgumentList "/s `"$selFile`"" -ErrorAction SilentlyContinue
                                    Write-Host "  [BASARILI] Kayit defteri geri yukleme basladi." -ForegroundColor Green
                                } else {
                                    Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor Yellow
                                }
                            } else {
                                Write-Host "  [BILGI] Yedek klasorunde .reg dosyasi bulunamadi." -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "  [BILGI] Yedek klasoru bulunamadi: $backupDir" -ForegroundColor Yellow
                            Write-Host "  Once '5. Kayit Defteri Yedekleme' ile bir yedek alin." -ForegroundColor DarkGray
                        }
                    }
                    7  {
                        # Windows Yedekleme ve Geri Yukleme (sdclt - Klasik)
                        Write-Host ""
                        Write-Host "  WINDOWS YEDEKLEME VE GERI YUKLEME (Klasik)" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        Write-Host "  Windows 7 tipi Yedekleme ve Geri Yukleme penceresi acilacak." -ForegroundColor White
                        Write-Host "  Buradan sistem goruntusu olusturabilir veya dosya yedegi alabilirsiniz." -ForegroundColor DarkGray
                        Write-Host ""
                        Start-QuickToolApp -CommandName "sdclt.exe" -ToolTitle "Yedekleme ve Geri Yukleme"
                    }
                    8  {
                        # Windows Yedekleme Ayarlari (Yeni - ms-settings)
                        Write-Host ""
                        Write-Host "  WINDOWS YEDEKLEME AYARLARI (Yeni)" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        Write-Host "  Windows 10/11 Yedekleme ayarlari penceresi acilacak." -ForegroundColor White
                        Write-Host "  OneDrive klasor senkronizasyonu ve cihaz tercihleri burada yonetilir." -ForegroundColor DarkGray
                        Write-Host ""
                        Start-QuickToolApp -CommandName "ms-settings:backup" -ToolTitle "Windows Yedekleme Ayarlari"
                    }
                    9  {
                        # Dosya Gecmisi (File History)
                        Write-Host ""
                        Write-Host "  DOSYA GECMISI (FILE HISTORY)" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        Write-Host "  Dosya Gecmisi Denetim Masasi penceresi acilacak." -ForegroundColor White
                        Write-Host "  Harici bir surucu bagladiginizda dosyalarinizin otomatik yedegin" -ForegroundColor DarkGray
                        Write-Host "  alinmasini saglayan Windows yerlesik ozelligi." -ForegroundColor DarkGray
                        Write-Host ""
                        Start-QuickToolApp -CommandName "control.exe" -Arguments "/name Microsoft.FileHistory" -ToolTitle "Dosya Gecmisi"
                    }
                    10 {
                        # Kurtarma Secenekleri
                        Write-Host ""
                        Write-Host "  KURTARMA SECENEKLERI" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        Write-Host "  Windows Kurtarma ayarlari acilacak." -ForegroundColor White
                        Write-Host "  Buradan bilgisayarinizi sifirlamaya veya Gelismis Baslangic" -ForegroundColor DarkGray
                        Write-Host "  seceneklerine erisebilirsiniz." -ForegroundColor DarkGray
                        Write-Host ""
                        Start-QuickToolApp -CommandName "ms-settings:recovery" -ToolTitle "Kurtarma Secenekleri"
                    }
                    11 {
                        # OneDrive / Bulut Yedekleme Durumu
                        Write-Host ""
                        Write-Host "  ONEDRIVE / BULUT YEDEKLEME DURUMU" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        # OneDrive sureci kontrol
                        $odProcess = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
                        if ($odProcess) {
                            Write-Host "  OneDrive Durumu  : " -ForegroundColor White -NoNewline
                            Write-Host "CALISIYOR (PID: $($odProcess.Id))" -ForegroundColor Green
                        } else {
                            Write-Host "  OneDrive Durumu  : " -ForegroundColor White -NoNewline
                            Write-Host "CALISMIYIOR veya YUKLU DEGIL" -ForegroundColor Yellow
                        }
                        # OneDrive klasor kontrolu
                        $odPaths = @(
                            (Join-Path $env:USERPROFILE "OneDrive"),
                            (Join-Path $env:USERPROFILE "OneDrive - Personal")
                        )
                        $odFound = $false
                        foreach ($odp in $odPaths) {
                            if (Test-Path $odp) {
                                $odFound = $true
                                $odItems = @(Get-ChildItem -Path $odp -Recurse -File -ErrorAction SilentlyContinue)
                                $totalSize = ($odItems | Measure-Object -Property Length -Sum).Sum
                                $sizeStr = if ($totalSize -gt 1GB) { "{0:N2} GB" -f ($totalSize / 1GB) } elseif ($totalSize -gt 1MB) { "{0:N1} MB" -f ($totalSize / 1MB) } else { "{0:N0} KB" -f ($totalSize / 1KB) }
                                Write-Host "  OneDrive Klasoru : " -ForegroundColor White -NoNewline
                                Write-Host "$odp" -ForegroundColor Green
                                Write-Host "  Toplam Dosya     : " -ForegroundColor White -NoNewline
                                Write-Host "$($odItems.Count) dosya ($sizeStr)" -ForegroundColor White
                            }
                        }
                        if (-not $odFound) {
                            Write-Host "  OneDrive Klasoru : " -ForegroundColor White -NoNewline
                            Write-Host "Bulunamadi" -ForegroundColor Yellow
                        }
                        Write-Host ""
                        # Dropbox ve Google Drive kontrol
                        $cloudServices = @(
                            @{ Name = "Dropbox";      Process = "Dropbox";      Paths = @("$env:USERPROFILE\Dropbox") },
                            @{ Name = "Google Drive";  Process = "GoogleDriveFS"; Paths = @("$env:USERPROFILE\Google Drive", "G:\My Drive") },
                            @{ Name = "iCloud Drive";  Process = "iCloudDrive";  Paths = @("$env:USERPROFILE\iCloudDrive") }
                        )
                        foreach ($svc in $cloudServices) {
                            $proc = Get-Process -Name $svc.Process -ErrorAction SilentlyContinue
                            $pathExists = $false
                            foreach ($sp in $svc.Paths) {
                                if (Test-Path $sp) { $pathExists = $true; break }
                            }
                            if ($proc -or $pathExists) {
                                $statusStr = if ($proc) { "CALISIYOR" } else { "Klasor mevcut (Suric kapali)" }
                                Write-Host "  $($svc.Name) : $statusStr" -ForegroundColor Green
                            }
                        }
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                    }
                    12 {
                        # Onemli Klasorlerin Yedegini Al
                        Write-Host ""
                        Write-Host "  ONEMLI KLASORLERIN YEDEGINI AL" -ForegroundColor Cyan
                        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                        $sourceFolders = @(
                            @{ Name = "Masaustu";   Path = [Environment]::GetFolderPath("Desktop") },
                            @{ Name = "Belgelerim"; Path = [Environment]::GetFolderPath("MyDocuments") },
                            @{ Name = "Resimlerim"; Path = [Environment]::GetFolderPath("MyPictures") },
                            @{ Name = "Indirilenler"; Path = (Join-Path $env:USERPROFILE "Downloads") }
                        )
                        Write-Host "  Yedeklenecek klasorler:" -ForegroundColor White
                        $fi = 1
                        foreach ($sf in $sourceFolders) {
                            $exists = Test-Path $sf.Path
                            $statusIcon = if ($exists) { "[+]" } else { "[-]" }
                            $statusColor = if ($exists) { "Green" } else { "DarkGray" }
                            Write-Host "  $statusIcon $fi. $($sf.Name): $($sf.Path)" -ForegroundColor $statusColor
                            $fi++
                        }
                        Write-Host ""
                        Write-Host "  Yedek klasorunun tam yolunu girin:" -ForegroundColor White
                        Write-Host "  (Orn: D:\Yedeklerim  veya  E:\AAU_Backup)" -ForegroundColor DarkGray
                        Write-Host "  Hedef: " -ForegroundColor Yellow -NoNewline
                        $targetRoot = Read-Host
                        if (-not $targetRoot) {
                            Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor Yellow
                        } else {
                            $targetRoot = $targetRoot.Trim('"')
                            $dateStr = Get-Date -Format "yyyy-MM-dd_HH-mm"
                            $backupRoot = Join-Path $targetRoot "AAU_Yedek_$dateStr"
                            Write-Host ""
                            Write-Host "  Yedekleme baslatiliyor: $backupRoot" -ForegroundColor Cyan
                            $totalCopied = 0
                            $totalErrors = 0
                            foreach ($sf in $sourceFolders) {
                                if (-not (Test-Path $sf.Path)) { continue }
                                $destDir = Join-Path $backupRoot $sf.Name
                                Write-Host "  Kopyalaniyor: $($sf.Name)... " -ForegroundColor White -NoNewline
                                try {
                                    if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
                                    $files = @(Get-ChildItem -Path $sf.Path -File -ErrorAction SilentlyContinue)
                                    foreach ($f in $files) {
                                        try {
                                            Copy-Item -Path $f.FullName -Destination $destDir -Force -ErrorAction Stop
                                            $totalCopied++
                                        } catch { $totalErrors++ }
                                    }
                                    Write-Host "$($files.Count) dosya" -ForegroundColor Green
                                } catch {
                                    Write-Host "HATA: $($_.Exception.Message)" -ForegroundColor Red
                                    $totalErrors++
                                }
                            }
                            Write-Host ""
                            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                            Write-Host "  [SONUC] Kopyalanan: $totalCopied dosya | Hata: $totalErrors" -ForegroundColor Green
                            Write-Host "  Hedef: $backupRoot" -ForegroundColor White
                            Write-LogInfo "Klasor yedekleme tamamlandi: $totalCopied dosya kopyalandi ($totalErrors hata) -> $backupRoot"
                        }
                    }
                    13 { Invoke-WifiProfileBackupRestore }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Yedekleme menusune donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category11 {
    $cat11Items = @(
        "Windows Defender Guvenlik Durumu",
        "Hizli Guvenlik Taramasi Baslat",
        "Defender Tanimlama ve Imza Guncelleme",
        "Windows Guvenlik Duvari (Firewall) Durumu",
        "Kullanici Hesabi Denetimi (UAC) Ayarlari",
        "Defender Klasor Dislama (Exclusion) Yonetimi"
    )
    $exitCat11 = $false
    while (-not $exitCat11) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [11] | Guvenlik Merkezi" -ForegroundColor Cyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat11Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Cyan -NoNewline
            Write-Host " $item" -ForegroundColor Cyan
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat11 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat11Items.Count) {
                $sel = $cat11Items[$idx - 1]
                Write-LogInfo "Kategori 11 secimi: [11.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [11] | Guvenlik Merkezi  >  [$ch] $sel" -ForegroundColor Cyan
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1 { Show-DefenderStatusCard }
                    2 { Invoke-DefenderQuickScanTool }
                    3 { Invoke-DefenderSignatureUpdateTool }
                    4 { Show-FirewallStatusCard }
                    5 { Invoke-OpenUacSettingsTool }
                    6 { Invoke-DefenderExclusionManager }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category12 {
    $cat12Items = @(
        "Baslangic Programlarini Yonetme","Gorsel Efektleri Optimize Etme",
        "Hizlandirilmis Baslangic (Fast Startup)","Uyku ve Hazirda Bekletme Ayarlari",
        "Oyun Modu Ayarlari","Disk Birlestiricisi","SSD TRIM Komutu",
        "Sayfalama Dosyasi (Pagefile) Ayari","CPU Guc Plani Optimizasyonu",
        "RAM Kullanim Raporu","Gereksiz Hizmetleri Devre Disi Birakma",
        "Windows Arama Hizmetini Yonetme","Superfetch (SysMain) Yonetimi","Ag Performansi Optimizasyonu",
        "Nihai Performans (Ultimate) Guc Plani","Hazirda Bekletme (Hibernation) Ac/Kapat",
        "Oyun Ince Ayarlari (GameDVR / HAGS / Fare)"
    )
    $exitCat12 = $false
    while (-not $exitCat12) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [12] | Performans Optimizasyonu" -ForegroundColor Cyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat12Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Cyan -NoNewline
            Write-Host " $item" -ForegroundColor Cyan
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat12 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat12Items.Count) {
                $sel = $cat12Items[$idx - 1]
                Write-LogInfo "Kategori 12 secimi: [12.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [12] | Performans Optimizasyonu  >  [$ch] $sel" -ForegroundColor Cyan
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1  { # Baslangic Programlarini Yonetme
                        Write-Host ""; Write-Host "  [BASLANGIC PROGRAMLARI]" -ForegroundColor Cyan
                        Write-Host ""
                        try {
                            Write-Host "  Baslangic programlari listeleniyor..." -ForegroundColor DarkCyan
                            $startups = Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object Name, Command, Location, User
                            if ($startups.Count -eq 0) {
                                Write-Host "  Kayitli baslangic programi bulunamadi." -ForegroundColor Yellow
                            } else {
                                Write-Host "  Toplam: $($startups.Count) baslangic programi bulundu." -ForegroundColor Green
                                Write-Host ""
                                $num = 1
                                foreach ($s in $startups) {
                                    Write-Host "  [$num] " -ForegroundColor Cyan -NoNewline
                                    Write-Host "$($s.Name)" -ForegroundColor White -NoNewline
                                    Write-Host " | $($s.Location)" -ForegroundColor DarkGray
                                    $num++
                                }
                            }
                        } catch {
                            Write-Host "  [HATA] Baslangic programlari alinamadi: $($_.Exception.Message)" -ForegroundColor Red
                        }
                        Write-Host ""
                        Write-Host "  [BILGI] Detayli yonetim icin Ayarlar aciliyor..." -ForegroundColor DarkCyan
                        Start-Sleep -Seconds 1
                        try { Start-Process "ms-settings:startupapps" -ErrorAction Stop } catch {}
                    }
                    2  { # Gorsel Efektleri Optimize Etme
                        Write-Host ""; Write-Host "  [GORSEL EFEKTLER]" -ForegroundColor Cyan
                        Write-Host "  Sistem Performans Ozellikleri penceresi aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "SystemPropertiesPerformance.exe" -ErrorAction Stop
                            Write-Host "  [BASARILI] Pencere acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    3  { # Hizlandirilmis Baslangic (Fast Startup)
                        Write-Host ""; Write-Host "  [HIZLI BASLANGIC]" -ForegroundColor Cyan
                        try {
                            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
                            $val = Get-ItemProperty -Path $regPath -Name "HiberbootEnabled" -ErrorAction Stop
                            $isOn = ($val.HiberbootEnabled -eq 1)
                            Write-Host "  Mevcut durum: " -ForegroundColor DarkCyan -NoNewline
                            Write-Host $(if ($isOn) { "[ACIK]" } else { "[KAPALI]" }) -ForegroundColor $(if ($isOn) { "Green" } else { "Yellow" })
                            if ($script:IsAdmin) {
                                $ans = Read-Host "  Durumu degistirmek ister misiniz? (E/H)"
                                if ($ans -and $ans.Trim().ToUpper() -eq "E") {
                                    $newVal = if ($isOn) { 0 } else { 1 }
                                    Set-ItemProperty -Path $regPath -Name "HiberbootEnabled" -Value $newVal -Type DWord -Force
                                    Write-Host "  [BASARILI] Hizli Baslangic $(if ($newVal -eq 1) { 'ACIK' } else { 'KAPALI' }) yapildi." -ForegroundColor Green
                                }
                            } else {
                                Write-Host "  [UYARI] Degisiklik icin yonetici yetkisi gerekir." -ForegroundColor Yellow
                            }
                        } catch {
                            Write-Host "  [BILGI] Hizli Baslangic durumu okunamadi." -ForegroundColor Yellow
                        }
                    }
                    4  { # Uyku ve Hazirda Bekletme
                        Write-Host ""; Write-Host "  [UYKU VE HAZIRDA BEKLETME]" -ForegroundColor Cyan
                        try {
                            $hibStatus = & powercfg /a 2>$null | Out-String
                            Write-Host "  Mevcut guc durumlari:" -ForegroundColor DarkCyan
                            Write-Host $hibStatus -ForegroundColor White
                        } catch {}
                        Write-Host "  Guc ve Uyku ayarlari aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "ms-settings:powersleep" -ErrorAction Stop } catch {}
                    }
                    5  { # Oyun Modu
                        Write-Host ""; Write-Host "  [OYUN MODU]" -ForegroundColor Cyan
                        Write-Host "  Oyun Modu ayarlari aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "ms-settings:gaming-gamemode" -ErrorAction Stop
                            Write-Host "  [BASARILI] Ayarlar acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    6  { # Disk Birlestiricisi
                        Write-Host ""; Write-Host "  [DISK BIRLESTIRICISI]" -ForegroundColor Cyan
                        Write-Host "  Disk Birlestiricisi aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "dfrgui.exe" -ErrorAction Stop
                            Write-Host "  [BASARILI] Disk Birlestiricisi acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    7  { # SSD TRIM
                        Write-Host ""; Write-Host "  [SSD TRIM]" -ForegroundColor Cyan
                        if ($script:IsAdmin) {
                            Write-Host "  C: surucusu icin TRIM komutu calistiriliyor..." -ForegroundColor DarkCyan
                            try {
                                Optimize-Volume -DriveLetter C -ReTrim -ErrorAction Stop
                                Write-Host "  [BASARILI] SSD TRIM komutu basariyla calistirildi." -ForegroundColor Green
                            } catch {
                                Write-Host "  [HATA] TRIM calistirilamadi: $($_.Exception.Message)" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "  [UYARI] SSD TRIM icin yonetici yetkisi gereklidir." -ForegroundColor Yellow
                            Write-Host "  Disk Birlestiricisi aciliyor (manuel TRIM icin)..." -ForegroundColor DarkCyan
                            try { Start-Process "dfrgui.exe" -ErrorAction Stop } catch {}
                        }
                    }
                    8  { # Sayfalama Dosyasi
                        Write-Host ""; Write-Host "  [SAYFALAMA DOSYASI (PAGEFILE)]" -ForegroundColor Cyan
                        try {
                            $pf = Get-CimInstance Win32_PageFileUsage -ErrorAction Stop
                            foreach ($p in $pf) {
                                Write-Host "  Dosya: " -ForegroundColor DarkCyan -NoNewline
                                Write-Host "$($p.Name)" -ForegroundColor White
                                Write-Host "  Kullanilan: " -ForegroundColor DarkCyan -NoNewline
                                Write-Host "$($p.CurrentUsage) MB / $($p.AllocatedBaseSize) MB" -ForegroundColor White
                            }
                        } catch { Write-Host "  [BILGI] Pagefile bilgisi alinamadi." -ForegroundColor Yellow }
                        Write-Host ""; Write-Host "  Sistem Ozellikleri aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "SystemPropertiesAdvanced.exe" -ErrorAction Stop } catch {}
                    }
                    9  { # CPU Guc Plani
                        Write-Host ""; Write-Host "  [CPU GUC PLANI]" -ForegroundColor Cyan
                        try {
                            $plans = & powercfg /list 2>$null
                            Write-Host "  Mevcut guc planlari:" -ForegroundColor DarkCyan; Write-Host ""
                            foreach ($line in $plans) {
                                if ($line -match '\*$') {
                                    Write-Host "  $line" -ForegroundColor Green
                                } elseif ($line.Trim()) {
                                    Write-Host "  $line" -ForegroundColor White
                                }
                            }
                            Write-Host ""
                            $hpAns = Read-Host "  Yuksek Performans (High Performance) planini aktiflestir? (E/H)"
                            if ($hpAns -and $hpAns.Trim().ToUpper() -eq "E") {
                                & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
                                Write-Host "  [BASARILI] Yuksek Performans guc plani uygulandi!" -ForegroundColor Green
                            }
                        } catch { Write-Host "  [HATA] Guc planlari alinamadi." -ForegroundColor Red }
                    }
                    10 { # RAM Kullanim Raporu
                        Write-Host ""; Write-Host "  [RAM KULLANIM RAPORU]" -ForegroundColor Cyan
                        try {
                            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                            $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
                            $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
                            $usedGB = [math]::Round($totalGB - $freeGB, 2)
                            $usedPct = [math]::Round(($usedGB / $totalGB) * 100, 1)
                            Write-Host ""
                            Write-Host "  Toplam RAM  : $totalGB GB" -ForegroundColor White
                            Write-Host "  Kullanilan  : $usedGB GB (%$usedPct)" -ForegroundColor $(if ($usedPct -gt 85) { "Red" } elseif ($usedPct -gt 60) { "Yellow" } else { "Green" })
                            Write-Host "  Bos         : $freeGB GB" -ForegroundColor Green
                            Write-Host ""
                            Write-Host "  En cok RAM kullanan 10 islem:" -ForegroundColor DarkCyan
                            Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object {
                                $mb = [math]::Round($_.WorkingSet64 / 1MB, 1)
                                Write-Host "    $($_.ProcessName.PadRight(30)) $mb MB" -ForegroundColor White
                            }
                        } catch { Write-Host "  [HATA] RAM bilgisi alinamadi." -ForegroundColor Red }
                    }
                    11 { # Gereksiz Hizmetler
                        Write-Host ""; Write-Host "  [HIZMET YONETIMI]" -ForegroundColor Cyan
                        Write-Host "  Windows Hizmetleri penceresi aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "services.msc" -ErrorAction Stop
                            Write-Host "  [BASARILI] Hizmetler penceresi acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    12 { # Windows Arama Hizmeti
                        Write-Host ""; Write-Host "  [WINDOWS ARAMA HIZMETI (WSearch)]" -ForegroundColor Cyan
                        try {
                            $svc = Get-Service -Name "WSearch" -ErrorAction Stop
                            $isRun = ($svc.Status -eq 'Running')
                            Write-Host "  Durum: [$($svc.Status)] ($($svc.StartType))" -ForegroundColor $(if ($isRun) { "Green" } else { "Yellow" })
                            if ($script:IsAdmin) {
                                $ans = Read-Host "  Hizmeti $(if ($isRun) { 'durdurup devre disi birak' } else { 'otomatik yapip baslat' })? (E/H)"
                                if ($ans -and $ans.Trim().ToUpper() -eq "E") {
                                    if ($isRun) { Stop-Service "WSearch" -Force -ErrorAction SilentlyContinue; Set-Service "WSearch" -StartupType Disabled }
                                    else { Set-Service "WSearch" -StartupType Automatic; Start-Service "WSearch" }
                                    Write-Host "  [BASARILI] WSearch guncellendi." -ForegroundColor Green
                                }
                            }
                        } catch { Write-Host "  [BILGI] WSearch hizmeti bulunamadi." -ForegroundColor Yellow }
                    }
                    13 { # Superfetch / SysMain
                        Write-Host ""; Write-Host "  [SUPERFETCH / SYSMAIN]" -ForegroundColor Cyan
                        try {
                            $svc = Get-Service -Name "SysMain" -ErrorAction Stop
                            $isRun = ($svc.Status -eq 'Running')
                            Write-Host "  Durum: [$($svc.Status)] ($($svc.StartType))" -ForegroundColor $(if ($isRun) { "Green" } else { "Yellow" })
                            if ($script:IsAdmin) {
                                $ans = Read-Host "  Hizmeti $(if ($isRun) { 'durdurup devre disi birak' } else { 'otomatik yapip baslat' })? (E/H)"
                                if ($ans -and $ans.Trim().ToUpper() -eq "E") {
                                    if ($isRun) { Stop-Service "SysMain" -Force -ErrorAction SilentlyContinue; Set-Service "SysMain" -StartupType Disabled }
                                    else { Set-Service "SysMain" -StartupType Automatic; Start-Service "SysMain" }
                                    Write-Host "  [BASARILI] SysMain guncellendi." -ForegroundColor Green
                                }
                            }
                        } catch { Write-Host "  [BILGI] SysMain hizmeti bulunamadi." -ForegroundColor Yellow }
                    }
                    14 { # Ag Performansi
                        Write-Host ""; Write-Host "  [AG PERFORMANSI]" -ForegroundColor Cyan
                        try {
                            $tcp = & netsh int tcp show global 2>$null | Out-String
                            Write-Host "  TCP Global Parametreleri:" -ForegroundColor DarkCyan
                            Write-Host $tcp -ForegroundColor White
                        } catch { Write-Host "  [HATA] TCP bilgisi alinamadi." -ForegroundColor Red }
                    }
                    15 { Invoke-UltimatePerformancePlan }
                    16 { Toggle-HibernationMode }
                    17 { Invoke-GamingPerformanceTweaks }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category13 {
    $cat13Items = @(
        "Yerel Kullanicilari Listeleme","Oturum Bilgilerini Goruntuleme",
        "Hesap Aktif/Pasif Yapma","Son Oturum Acma Suresi",
        "Microsoft Hesabi Yonetimi","Windows Hello PIN Yonetimi",
        "Yeni Kullanici Olusturma","Kullanici Sifresi Degistirme",
        "Kullanici Silme","Kullanici Gruplarina Atama","Yonetici Yetkisi Verme/Alma"
    )
    $exitCat13 = $false
    while (-not $exitCat13) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [13] | Kullanici Yonetimi" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat13Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Magenta -NoNewline
            Write-Host " $item" -ForegroundColor Magenta
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat13 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat13Items.Count) {
                $sel = $cat13Items[$idx - 1]
                Write-LogInfo "Kategori 13 secimi: [13.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [13] | Kullanici Yonetimi  >  [$ch] $sel" -ForegroundColor Magenta
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1  { # Yerel Kullanicilari Listeleme
                        Write-Host ""; Write-Host "  [YEREL KULLANICILAR]" -ForegroundColor Magenta
                        Write-Host ""
                        try {
                            $users = Get-LocalUser -ErrorAction Stop
                            Write-Host "  Toplam: $($users.Count) kullanici hesabi" -ForegroundColor Green; Write-Host ""
                            Write-Host ("  " + "Ad".PadRight(25) + "Durum".PadRight(12) + "Son Oturum") -ForegroundColor DarkCyan
                            Write-Host ("  " + ("-"*25) + " " + ("-"*11) + " " + ("-"*20)) -ForegroundColor DarkGray
                            foreach ($u in $users) {
                                $status = if ($u.Enabled) { "Aktif" } else { "Pasif" }
                                $statusColor = if ($u.Enabled) { "Green" } else { "DarkGray" }
                                $lastLogon = if ($u.LastLogon) { $u.LastLogon.ToString("yyyy-MM-dd HH:mm") } else { "-" }
                                Write-Host "  " -NoNewline
                                Write-Host $u.Name.PadRight(25) -ForegroundColor White -NoNewline
                                Write-Host $status.PadRight(12) -ForegroundColor $statusColor -NoNewline
                                Write-Host $lastLogon -ForegroundColor DarkCyan
                            }
                        } catch {
                            Write-Host "  [HATA] Kullanici listesi alinamadi: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                    2  { # Oturum Bilgileri
                        Write-Host ""; Write-Host "  [OTURUM BILGILERI]" -ForegroundColor Magenta; Write-Host ""
                        try {
                            $quser = & query user 2>$null
                            if ($quser) {
                                foreach ($line in $quser) { Write-Host "  $line" -ForegroundColor White }
                            } else { Write-Host "  [BILGI] Aktif oturum bilgisi alinamadi." -ForegroundColor Yellow }
                        } catch { Write-Host "  [BILGI] query user komutu calistirilamadi." -ForegroundColor Yellow }
                    }
                    3  { # Hesap Aktif/Pasif
                        Write-Host ""; Write-Host "  [HESAP DURUMU DEGISTIRME]" -ForegroundColor Magenta
                        if (-not $script:IsAdmin) {
                            Write-Host "  [UYARI] Bu islem icin yonetici yetkisi gereklidir." -ForegroundColor Yellow
                        } else {
                            try {
                                $users = Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -ne $env:USERNAME }
                                Write-Host ""
                                $num = 1
                                foreach ($u in $users) {
                                    $st = if ($u.Enabled) { "[Aktif]" } else { "[Pasif]" }
                                    $stC = if ($u.Enabled) { "Green" } else { "DarkGray" }
                                    Write-Host "  [$num] $($u.Name) " -ForegroundColor White -NoNewline
                                    Write-Host $st -ForegroundColor $stC
                                    $num++
                                }
                                Write-Host ""; Write-Host "  Degistirilecek kullanici numarasi (0=Iptal): " -ForegroundColor Yellow -NoNewline
                                $sel2 = Read-Host
                                if ($sel2 -match "^\d+$" -and [int]$sel2 -ge 1 -and [int]$sel2 -le $users.Count) {
                                    $target = $users[[int]$sel2 - 1]
                                    if ($target.Enabled) {
                                        Disable-LocalUser -Name $target.Name -ErrorAction Stop
                                        Write-Host "  [BASARILI] $($target.Name) pasif yapildi." -ForegroundColor Green
                                    } else {
                                        Enable-LocalUser -Name $target.Name -ErrorAction Stop
                                        Write-Host "  [BASARILI] $($target.Name) aktif yapildi." -ForegroundColor Green
                                    }
                                }
                            } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                        }
                    }
                    4  { # Son Oturum Acma
                        Write-Host ""; Write-Host "  [SON OTURUM ACMA BILGILERI]" -ForegroundColor Magenta; Write-Host ""
                        try {
                            $users = Get-LocalUser -ErrorAction Stop
                            foreach ($u in $users) {
                                $lastLogon = if ($u.LastLogon) { $u.LastLogon.ToString("yyyy-MM-dd HH:mm:ss") } else { "Hic oturum acilmadi" }
                                Write-Host "  $($u.Name.PadRight(25))" -ForegroundColor White -NoNewline
                                Write-Host $lastLogon -ForegroundColor DarkCyan
                            }
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    5  { # Microsoft Hesabi
                        Write-Host ""; Write-Host "  [MICROSOFT HESABI]" -ForegroundColor Magenta
                        Write-Host "  Microsoft Hesap ayarlari aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "ms-settings:yourinfo" -ErrorAction Stop
                            Write-Host "  [BASARILI] Ayarlar acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    6  { # Windows Hello PIN
                        Write-Host ""; Write-Host "  [WINDOWS HELLO / PIN]" -ForegroundColor Magenta
                        Write-Host "  Oturum acma secenekleri aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "ms-settings:signinoptions" -ErrorAction Stop
                            Write-Host "  [BASARILI] Ayarlar acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    7  { # Yeni Kullanici Olusturma
                        Write-Host ""; Write-Host "  [YENI KULLANICI OLUSTURMA]" -ForegroundColor Magenta
                        if (-not $script:IsAdmin) {
                            Write-Host "  [UYARI] Bu islem icin yonetici yetkisi gereklidir." -ForegroundColor Yellow
                        } else {
                            $uName = Read-Host "  Yeni kullanici adi (bos=Iptal)"
                            if (-not [string]::IsNullOrWhiteSpace($uName)) {
                                $uPass = Read-Host "  Sifre (bos birakilabilir)" -AsSecureString
                                try {
                                    if ($uPass.Length -gt 0) {
                                        $null = New-LocalUser -Name $uName.Trim() -Password $uPass -PasswordNeverExpires -ErrorAction Stop
                                    } else {
                                        $null = New-LocalUser -Name $uName.Trim() -NoPassword -ErrorAction Stop
                                    }
                                    $usersGrp = (Get-LocalGroup -SID "S-1-5-32-545" -ErrorAction SilentlyContinue).Name
                                    if ($usersGrp) { Add-LocalGroupMember -Group $usersGrp -Member $uName.Trim() -ErrorAction SilentlyContinue }
                                    Write-Host "  [BASARILI] '$($uName.Trim())' kullanicisi olusturuldu!" -ForegroundColor Green
                                } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                            }
                        }
                    }
                    8  { # Sifre Degistirme
                        Write-Host ""; Write-Host "  [KULLANICI SIFRESI DEGISTIRME]" -ForegroundColor Magenta
                        if (-not $script:IsAdmin) {
                            Write-Host "  [UYARI] Bu islem icin yonetici yetkisi gereklidir." -ForegroundColor Yellow
                        } else {
                            try {
                                $users = @(Get-LocalUser -ErrorAction Stop)
                                for ($ui = 0; $ui -lt $users.Count; $ui++) { Write-Host "  [$($ui+1)] $($users[$ui].Name)" -ForegroundColor White }
                                $pick = Read-Host "  Kullanici numarasi (0=Iptal)"
                                if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $users.Count) {
                                    $target = $users[[int]$pick - 1]
                                    $newPass = Read-Host "  '$($target.Name)' icin yeni sifre" -AsSecureString
                                    Set-LocalUser -Name $target.Name -Password $newPass -ErrorAction Stop
                                    Write-Host "  [BASARILI] '$($target.Name)' sifresi guncellendi." -ForegroundColor Green
                                }
                            } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                        }
                    }
                    9  { # Kullanici Silme
                        Write-Host ""; Write-Host "  [KULLANICI SILME]" -ForegroundColor Magenta
                        if (-not $script:IsAdmin) {
                            Write-Host "  [UYARI] Bu islem icin yonetici yetkisi gereklidir." -ForegroundColor Yellow
                        } else {
                            try {
                                $users = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -ne $env:USERNAME -and $_.Name -notin @('Administrator','Guest','DefaultAccount','WDAGUtilityAccount') })
                                if ($users.Count -eq 0) {
                                    Write-Host "  [BILGI] Silinebilir baska yerel kullanici bulunamadi." -ForegroundColor Yellow
                                } else {
                                    for ($ui = 0; $ui -lt $users.Count; $ui++) { Write-Host "  [$($ui+1)] $($users[$ui].Name)" -ForegroundColor White }
                                    $pick = Read-Host "  Silinecek kullanici numarasi (0=Iptal)"
                                    if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $users.Count) {
                                        $target = $users[[int]$pick - 1]
                                        $conf = Read-Host "  '$($target.Name)' silinecek! Onayliyor musunuz? (E/H)"
                                        if ($conf -and $conf.Trim().ToUpper() -eq "E") {
                                            Remove-LocalUser -Name $target.Name -ErrorAction Stop
                                            Write-Host "  [BASARILI] '$($target.Name)' silindi." -ForegroundColor Green
                                        }
                                    }
                                }
                            } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                        }
                    }
                    10 { # Grup Atama
                        Write-Host ""; Write-Host "  [YEREL GRUPLAR]" -ForegroundColor Magenta
                        try {
                            Get-LocalGroup -ErrorAction Stop | ForEach-Object {
                                $members = @(Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ", "
                                Write-Host "  - $($_.Name): " -ForegroundColor Cyan -NoNewline
                                Write-Host $(if ($members) { $members } else { "(bos)" }) -ForegroundColor White
                            }
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    11 { # Yonetici Yetkisi
                        Write-Host ""; Write-Host "  [YONETICI YETKISI VERME / ALMA]" -ForegroundColor Magenta
                        if (-not $script:IsAdmin) {
                            Write-Host "  [UYARI] Bu islem icin yonetici yetkisi gereklidir." -ForegroundColor Yellow
                        } else {
                            try {
                                $adminGrp = (Get-LocalGroup -SID "S-1-5-32-544" -ErrorAction Stop).Name
                                $adminMembers = @(Get-LocalGroupMember -Group $adminGrp -ErrorAction SilentlyContinue | ForEach-Object { ($_.Name -split '\\')[-1] })
                                $users = @(Get-LocalUser -ErrorAction Stop | Where-Object { $_.Name -ne $env:USERNAME })
                                for ($ui = 0; $ui -lt $users.Count; $ui++) {
                                    $isAdm = $users[$ui].Name -in $adminMembers
                                    Write-Host "  [$($ui+1)] $($users[$ui].Name) " -ForegroundColor White -NoNewline
                                    Write-Host $(if ($isAdm) { "[Yonetici]" } else { "[Standart]" }) -ForegroundColor $(if ($isAdm) { "Green" } else { "DarkGray" })
                                }
                                $pick = Read-Host "  Yetkisi degistirilecek kullanici numarasi (0=Iptal)"
                                if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $users.Count) {
                                    $target = $users[[int]$pick - 1]
                                    if ($target.Name -in $adminMembers) {
                                        Remove-LocalGroupMember -Group $adminGrp -Member $target.Name -ErrorAction Stop
                                        Write-Host "  [BASARILI] $($target.Name) yonetici grubundan cikarildi." -ForegroundColor Yellow
                                    } else {
                                        Add-LocalGroupMember -Group $adminGrp -Member $target.Name -ErrorAction Stop
                                        Write-Host "  [BASARILI] $($target.Name) yonetici yapildi." -ForegroundColor Green
                                    }
                                }
                            } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                        }
                    }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category14 {
    $cat14Items = @(
        "SFC Taramasi (sfc /scannow)",
        "DISM Saglik Kontrolu (CheckHealth)",
        "DISM Sistem Onarimi (RestoreHealth)",
        "Disk Hata Kontrolu (chkdsk /scan)",
        "Windows Bellek Tani Araci (mdsched)",
        "Windows Update Onbellegini Sifirla"
    )
    $exitCat14 = $false
    while (-not $exitCat14) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [14] | Tani ve Onarim" -ForegroundColor Cyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat14Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Cyan -NoNewline
            Write-Host " $item" -ForegroundColor Cyan
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat14 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat14Items.Count) {
                $sel = $cat14Items[$idx - 1]
                Write-LogInfo "Kategori 14 secimi: [14.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [14] | Tani ve Onarim  >  [$ch] $sel" -ForegroundColor Cyan
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1 { Invoke-SfcScanTool }
                    2 { Invoke-DismCheckTool }
                    3 { Invoke-DismRepairTool }
                    4 { Invoke-ChkdskScanTool }
                    5 { Invoke-MemoryDiagnosticTool }
                    6 {
                        Write-Host "`n  [WINDOWS UPDATE ONBELLEK SIFIRLAMA]" -ForegroundColor Cyan
                        if (-not $script:IsAdmin) {
                            Write-Host "  [UYARI] Bu islem icin yonetici yetkisi gerekir." -ForegroundColor Yellow
                        } else {
                            try {
                                Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
                                $dlPath = "$env:SystemRoot\SoftwareDistribution\Download"
                                if (Test-Path $dlPath) {
                                    Remove-Item -Path "$dlPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                                }
                                Start-Service -Name bits, wuauserv -ErrorAction SilentlyContinue
                                Write-Host "  [BASARILI] Windows Update indirme onbellegi temizlendi." -ForegroundColor Green
                                Write-LogSuccess "Windows Update onbellegi sifirlandi."
                            } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                        }
                    }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category15 {
    $cat15Items = @(
        "Disk Kullanim Analizi","En Buyuk Dosyalari Bulma","Buyuk Klasorleri Listeleme",
        "Surucuyu Acma","Dosya Sistemi Kontrolu (chkdsk)","Disk Birlestiricisi",
        "Ag Surucu Baglama","BitLocker Durumu","Disk Yonetimi",
        "Depolama Alani Ayarlari","Veri Kurtarma Ipuclari"
    )
    $exitCat15 = $false
    while (-not $exitCat15) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [15] | Depolama Yonetimi" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat15Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Magenta -NoNewline
            Write-Host " $item" -ForegroundColor Magenta
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat15 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat15Items.Count) {
                $sel = $cat15Items[$idx - 1]
                Write-LogInfo "Kategori 15 secimi: [15.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [15] | Depolama Yonetimi  >  [$ch] $sel" -ForegroundColor Magenta
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1  { # Disk Kullanim Analizi
                        Write-Host ""; Write-Host "  [DISK KULLANIM ANALIZI]" -ForegroundColor Magenta; Write-Host ""
                        try {
                            $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
                            foreach ($d in $disks) {
                                $totalGB = [math]::Round($d.Size / 1GB, 2)
                                $freeGB = [math]::Round($d.FreeSpace / 1GB, 2)
                                $usedGB = [math]::Round($totalGB - $freeGB, 2)
                                $usedPct = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }
                                $barLen = 40
                                $filled = [int]($barLen * $usedPct / 100)
                                $empty = $barLen - $filled
                                $bar = ("█" * $filled) + ("░" * $empty)
                                $pctColor = if ($usedPct -gt 90) { "Red" } elseif ($usedPct -gt 70) { "Yellow" } else { "Green" }
                                Write-Host "  Surucu $($d.DeviceID) [$($d.VolumeName)]" -ForegroundColor White
                                Write-Host "  [$bar] %$usedPct" -ForegroundColor $pctColor
                                Write-Host "  Toplam: $totalGB GB | Kullanilan: $usedGB GB | Bos: $freeGB GB" -ForegroundColor DarkCyan
                                Write-Host ""
                            }
                        } catch { Write-Host "  [HATA] Disk bilgisi alinamadi: $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    2  { # En Buyuk Dosyalar
                        Write-Host ""; Write-Host "  [EN BUYUK DOSYALAR]" -ForegroundColor Magenta
                        Write-Host "  C: surucusunde en buyuk 15 dosya aranıyor..." -ForegroundColor DarkCyan
                        Write-Host "  (Bu islem birkac dakika surebilir)" -ForegroundColor DarkGray; Write-Host ""
                        try {
                            $bigFiles = Get-ChildItem -Path "C:\" -Recurse -File -ErrorAction SilentlyContinue |
                                Sort-Object Length -Descending | Select-Object -First 15
                            $num = 1
                            foreach ($f in $bigFiles) {
                                $sizeMB = [math]::Round($f.Length / 1MB, 1)
                                $sizeStr = if ($sizeMB -gt 1024) { "$([math]::Round($sizeMB/1024,1)) GB" } else { "$sizeMB MB" }
                                Write-Host "  [$($num.ToString().PadLeft(2))] $sizeStr".PadRight(18) -ForegroundColor White -NoNewline
                                Write-Host " $($f.FullName)" -ForegroundColor DarkCyan
                                $num++
                            }
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    3  { # Buyuk Klasorler
                        Write-Host ""; Write-Host "  [BUYUK KLASORLER]" -ForegroundColor Magenta
                        Write-Host "  C:\ altindaki ana klasor boyutlari hesaplaniyor..." -ForegroundColor DarkCyan; Write-Host ""
                        try {
                            $folders = Get-ChildItem -Path "C:\" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                                $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                                [PSCustomObject]@{ Name = $_.Name; SizeGB = [math]::Round($size / 1GB, 2) }
                            } | Sort-Object SizeGB -Descending | Select-Object -First 10
                            foreach ($f in $folders) {
                                $bar = "█" * [math]::Min(30, [int]($f.SizeGB * 2))
                                Write-Host "  $($f.Name.PadRight(25))" -ForegroundColor White -NoNewline
                                Write-Host "$($f.SizeGB) GB " -ForegroundColor Cyan -NoNewline
                                Write-Host $bar -ForegroundColor DarkCyan
                            }
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    4  { # Surucuyu Acma
                        Write-Host ""; Write-Host "  [SURUCU ACMA]" -ForegroundColor Magenta; Write-Host ""
                        try {
                            $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
                            $num = 1
                            foreach ($d in $disks) {
                                Write-Host "  [$num] $($d.DeviceID) - $($d.VolumeName)" -ForegroundColor White
                                $num++
                            }
                            Write-Host ""; Write-Host "  Acilacak surucu numarasi (0=Iptal): " -ForegroundColor Yellow -NoNewline
                            $sel2 = Read-Host
                            if ($sel2 -match "^\d+$" -and [int]$sel2 -ge 1 -and [int]$sel2 -le $disks.Count) {
                                $target = $disks[[int]$sel2 - 1]
                                Start-Process "explorer.exe" -ArgumentList "$($target.DeviceID)\" -ErrorAction Stop
                                Write-Host "  [BASARILI] $($target.DeviceID) acildi." -ForegroundColor Green
                            }
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    5  { # Dosya Sistemi Kontrolu
                        Write-Host ""; Write-Host "  [DOSYA SISTEMI KONTROLU]" -ForegroundColor Magenta
                        if (-not $script:IsAdmin) {
                            Write-Host "  [UYARI] chkdsk icin yonetici yetkisi gereklidir." -ForegroundColor Yellow
                        } else {
                            Write-Host "  C: surucusu icin chkdsk /scan calistiriliyor..." -ForegroundColor DarkCyan
                            try {
                                $result = & chkdsk C: /scan 2>&1 | Out-String
                                Write-Host $result -ForegroundColor White
                            } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                        }
                    }
                    6  { # Disk Birlestiricisi
                        Write-Host ""; Write-Host "  [DISK BIRLESTIRICISI]" -ForegroundColor Magenta
                        Write-Host "  Disk Birlestiricisi aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "dfrgui.exe" -ErrorAction Stop
                            Write-Host "  [BASARILI] Acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    7  { # Ag Surucu Baglama
                        Write-Host ""; Write-Host "  [AG SURUCU BAGLAMA]" -ForegroundColor Magenta
                        Write-Host "  Mevcut ag surucileri:" -ForegroundColor DarkCyan; Write-Host ""
                        try {
                            $netDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot -match '\\\\' }
                            if ($netDrives) {
                                foreach ($nd in $netDrives) {
                                    Write-Host "  $($nd.Name): -> $($nd.DisplayRoot)" -ForegroundColor White
                                }
                            } else { Write-Host "  Bagli ag surucusu bulunamadi." -ForegroundColor DarkGray }
                        } catch {}
                        Write-Host ""; Write-Host "  Ag Surucu Baglama penceresi aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "rundll32.exe" -ArgumentList "shell32.dll,SHHelpShortcuts_RunDLL Connect" -ErrorAction Stop } catch {}
                    }
                    8  { # BitLocker Durumu
                        Write-Host ""; Write-Host "  [BITLOCKER DURUMU]" -ForegroundColor Magenta; Write-Host ""
                        try {
                            $bl = & manage-bde -status 2>$null | Out-String
                            if ($bl) { Write-Host $bl -ForegroundColor White }
                            else { Write-Host "  [BILGI] BitLocker bilgisi alinamadi." -ForegroundColor Yellow }
                        } catch { Write-Host "  [BILGI] BitLocker bu sistemde desteklenmiyor olabilir." -ForegroundColor Yellow }
                    }
                    9  { # Disk Yonetimi
                        Write-Host ""; Write-Host "  [DISK YONETIMI]" -ForegroundColor Magenta
                        Write-Host "  Disk Yonetimi aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "diskmgmt.msc" -ErrorAction Stop
                            Write-Host "  [BASARILI] Acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    10 { # Depolama Alani Ayarlari
                        Write-Host ""; Write-Host "  [DEPOLAMA ALANI AYARLARI]" -ForegroundColor Magenta
                        Write-Host "  Depolama ayarlari aciliyor..." -ForegroundColor DarkCyan
                        try { Start-Process "ms-settings:storagesense" -ErrorAction Stop
                            Write-Host "  [BASARILI] Acildi." -ForegroundColor Green
                        } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
                    }
                    11 { # Veri Kurtarma Ipuclari
                        Write-Host ""; Write-Host "  [VERI KURTARMA IPUCLARI]" -ForegroundColor Magenta
                        Write-Host ""
                        Write-Host "  Windows yerlesik veri kurtarma yontemleri:" -ForegroundColor DarkCyan
                        Write-Host ""
                        Write-Host "  1. Geri Donusum Kutusu  : Silinen dosyalar once buraya gider." -ForegroundColor White
                        Write-Host "  2. Dosya Gecmisi        : Ayarlar > Guncellestirme > Yedekleme" -ForegroundColor White
                        Write-Host "  3. Onceki Surumler      : Dosya/klasor > Sag tik > Ozellikler > Onceki Surumler" -ForegroundColor White
                        Write-Host "  4. Sistem Geri Yukleme  : rstrui.exe (Geri Yukleme Noktasi)" -ForegroundColor White
                        Write-Host "  5. Windows File Recovery : Microsoft Store'dan indirilebilir (winfr komutu)" -ForegroundColor White
                        Write-Host ""
                        Write-Host "  [ONEMLI] Veri kaybinda diskte yazma islemi yapmayin!" -ForegroundColor Yellow
                        Write-Host "  [ONEMLI] Profesyonel kurtarma icin diske mudahale etmeyin." -ForegroundColor Yellow
                    }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category16 {
    $cat16Items = @(
        "WinGet Program Guncellemelerini Listele",
        "Tum Programlari Guncelle (winget upgrade --all)",
        "Windows Update Ayarlarini Ac"
    )
    $exitCat16 = $false
    while (-not $exitCat16) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [16] | Sistem ve Program Guncellemeleri" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat16Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Magenta -NoNewline
            Write-Host " $item" -ForegroundColor Magenta
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat16 = $true
        } elseif ($ch -match "^\d+$") {
            $idx = [int]$ch
            if ($idx -ge 1 -and $idx -le $cat16Items.Count) {
                $sel = $cat16Items[$idx - 1]
                Write-LogInfo "Kategori 16 secimi: [16.$ch] $sel"
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable; Write-Host ""
                Write-Host "  [16] | Sistem ve Program Guncellemeleri  >  [$ch] $sel" -ForegroundColor Magenta
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                switch ($idx) {
                    1 { Show-WinGetUpdatesView }
                    2 { Invoke-WinGetUpdateAllAction }
                    3 { Invoke-OpenWindowsUpdateSettings }
                }
                Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            } else {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category17 {
    $cat17Items = @(
        "Son Islem Gunlugunu Goruntuleme",
        "Kurulum Gecmisi (Detayli)",
        "Eski Log Dosyalarini Silme ve Temizlik"
    )
    $exitCat17 = $false
    while (-not $exitCat17) {
        Show-ScreenTransition
        Show-AppHeader; Write-Host ""
        Write-Host "  [17] | Islem Gecmisi ve Gunluk Yonetimi" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $cat17Items) {
            $numTag = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            Write-Host "  $numTag" -ForegroundColor Magenta -NoNewline
            Write-Host " $item" -ForegroundColor Magenta
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitCat17 = $true
        } elseif ($ch -eq "1" -or $ch -eq "01") {
            Show-LogInConsole -LogPath $script:LogFilePath
        } elseif ($ch -eq "2" -or $ch -eq "02") {
            Write-LogInfo "Kategori 17 secimi: [17.2] Kurulum Gecmisi (Detayli)"
            try {
                Show-InstallHistory
            } catch {
                Write-Host "  [BILGI] Kurulum gecmisi modulu yuklenemedi." -ForegroundColor Yellow
                Write-Host "  Hata: $($_.Exception.Message)" -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
            }
        } elseif ($ch -eq "3" -or $ch -eq "03" -or $ch -eq "9") {
            Show-LogCleanupMenu
        } else {
            Write-Host "  [HATA] Gecersiz giris." -ForegroundColor Red; Start-Sleep -Seconds 1
        }
    }
}
function Invoke-Category18 {
    if (Get-Command "Invoke-SettingsManagement" -ErrorAction SilentlyContinue) {
        Invoke-SettingsManagement
    } else {
        Write-Host "`n  [HATA] Ayarlar modulu (admin_profiles.psm1) yuklenemedi." -ForegroundColor Red
        Wait-UserKeyPress
    }
}

# ============================================================================
# AAU YONETICI PANELI (ADMIN MENU VE ISLEVLERI)
# ============================================================================

function Show-AdminMenu {
    Show-ScreenTransition -IsAdmin
    Clear-Host
    try { $host.UI.RawUI.WindowPosition = New-Object System.Management.Automation.Host.Coordinates(0, 0) } catch {}
    # Tampon yuksekligini pencere boyutuna esitleyerek kaydirma cubugunu kaldir
    try {
        $rawUI = $host.UI.RawUI
        $winH = $rawUI.WindowSize.Height
        if ($winH -gt 0) {
            $buf = $rawUI.BufferSize
            $buf.Height = $winH
            $rawUI.BufferSize = $buf
        }
    } catch {}
    Show-AppBanner -Indent 14
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "="
    Write-Host "  USER: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($env:USERNAME)" -ForegroundColor White -NoNewline
    Write-Host "  |  PC: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($env:COMPUTERNAME)" -ForegroundColor White -NoNewline
    Write-Host "  |  PS: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" -ForegroundColor White -NoNewline
    Write-Host "  |  ARCH: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$script:OSArch" -ForegroundColor White -NoNewline
    Write-Host "  |  YETKI: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "[YONETICI (ADMIN MODU)]" -ForegroundColor Magenta
    Write-Host "  CURRENT OS: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$script:OSName" -ForegroundColor White -NoNewline
    Write-Host "  |  SURUM: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "v$script:AppVersion" -ForegroundColor Green -NoNewline
    Write-Host "  |  DEFENDER PROTOKOLU" -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "="
    Write-Host "  AAU YONETICI PANELI - IDARI SISTEM VE VERITABANI YONETIMI" -ForegroundColor Magenta
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

    # 2 sutunlu kategori secimi (12 secenek)
    Write-Host "  " -NoNewline
    Write-Host ("KATALOG | PROFIL YONETIMI".PadRight(38)) -ForegroundColor Magenta -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "SISTEM | LOG & BAKIM YONETIMI" -ForegroundColor Magenta
    Write-Host ("  " + ("-"*38) + "    " + ("-"*38)) -ForegroundColor DarkCyan

    Write-Host "  " -NoNewline
    Write-Host ("[ 1] | Uygulama Katalogu Goruntule".PadRight(38)) -ForegroundColor Magenta -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "[ 7] | Log Dosyalarini Goruntule" -ForegroundColor Magenta

    Write-Host "  " -NoNewline
    Write-Host ("[ 2] | Yeni Uygulama Ekle".PadRight(38)) -ForegroundColor Magenta -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "[ 8] | Eski Loglari Sil" -ForegroundColor Magenta

    Write-Host "  " -NoNewline
    Write-Host ("[ 3] | Uygulamayi Duzenle".PadRight(38)) -ForegroundColor Magenta -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "[ 9] | Kurulum Ayarlari" -ForegroundColor Magenta

    Write-Host "  " -NoNewline
    Write-Host ("[ 4] | Uygulamayi Sil".PadRight(38)) -ForegroundColor Magenta -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "[10] | Yedekleme ve Geri Yukleme" -ForegroundColor Magenta

    Write-Host "  " -NoNewline
    Write-Host ("[ 5] | Kategori Yonetimi".PadRight(38)) -ForegroundColor Magenta -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "[11] | Modul Durumu Raporu" -ForegroundColor Magenta

    Write-Host "  " -NoNewline
    Write-Host ("[ 6] | Profil Yonetimi".PadRight(38)) -ForegroundColor Magenta -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "[12] | Proje Klasorunu Ac" -ForegroundColor Magenta

    Write-Host ""
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host "  " -NoNewline
    Write-Host ("[13] | Kullanici Paneline Gec".PadRight(38)) -ForegroundColor Cyan -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "[20] | Hakkinda" -ForegroundColor Yellow
    Write-Host "  " -NoNewline
    Write-Host ("".PadRight(38)) -NoNewline
    Write-Host "    " -NoNewline
    Write-Host "[ 0] | Cikis  [ESC]" -ForegroundColor Red
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
}

function Show-AdminCategoryAppsView {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Category,
        [Parameter(Mandatory)][PSCustomObject]$Catalog
    )

    $catId = $Category.id
    $catName = $Category.name
    $catIcon = if ($Category.icon) { $Category.icon } else { "📁" }

    $exitCatLoop = $false
    while (-not $exitCatLoop) {
        $allApps = @($Catalog.applications)
        $appsInCat = @($allApps | Where-Object { "$($_.Category)".ToLower() -eq $catId.ToLower() } | Sort-Object @{
            Expression = { if ($null -ne $_.InstallOrder) { [int]$_.InstallOrder } else { 9999 } }
        }, Name)

        Show-ScreenTransition -IsAdmin -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  $catIcon $catName ($catId)" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        if ($appsInCat.Count -eq 0) {
            Write-Host "  [BILGI] Bu kategoride henuz kayitli program bulunmuyor." -ForegroundColor Yellow
            Write-Host ""
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Kategorilere donmek icin bir tusa basin..."
            return
        }

        $j = 1
        foreach ($app in $appsInCat) {
            $numTag = "[$j]".PadRight(4)
            $src = if ($app.Source -eq "msstore") { "[Store]" } else { "[WinGet]" }
            $en  = if ($app.Enabled) { "" } else { " [PASIF]" }
            $enColor = if ($app.Enabled) { [ConsoleColor]::White } else { [ConsoleColor]::DarkGray }

            Write-Host "    $numTag " -ForegroundColor Magenta -NoNewline
            Write-Host "$($app.Name)".PadRight(30) -ForegroundColor $enColor -NoNewline
            Write-Host "$src".PadRight(10) -ForegroundColor Cyan -NoNewline
            Write-Host "($($app.Id))$en" -ForegroundColor DarkCyan
            $j++
        }

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host "  Detay incelemek veya islem yapmak icin program secin [1-$($appsInCat.Count)]:" -ForegroundColor Yellow
        Write-Host "  [G] Kategorilere Don" -ForegroundColor Magenta
        Write-Host "  [0] Yonetici Paneline Don" -ForegroundColor Red
        Write-Host ""
        $pChoice = Read-MenuInput
        $pVal = if ($null -ne $pChoice) { $pChoice.Trim().ToUpper() } else { "" }

        if ($pVal -eq "ESC" -or $pVal -eq "0" -or $pVal -eq "00") {
            return
        } elseif ($pVal -eq "G" -or $pVal -eq "B") {
            return
        } elseif ($pVal -match '^\d+$') {
            $pIdx = [int]$pVal
            if ($pIdx -ge 1 -and $pIdx -le $appsInCat.Count) {
                $chosenApp = $appsInCat[$pIdx - 1]
                Show-AppDetailCard -App $chosenApp -Catalog $Catalog
            } else {
                Write-Host "  [HATA] Gecersiz program numarasi." -ForegroundColor Red
                Start-Sleep -Milliseconds 800
            }
        } else {
            Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red
            Start-Sleep -Milliseconds 800
        }
    }
}

function Invoke-AdminOption01 {
    Write-LogInfo "Admin secimi: [1] Uygulama Katalogu Goruntule"
    $exitCatalogSub = $false
    while (-not $exitCatalogSub) {
        $catalog = Import-AppCatalog
        if (-not $catalog -or -not $catalog.applications) {
            Write-Host "  [HATA] Uygulama katalogu bulunamadi!" -ForegroundColor Red
            Wait-UserKeyPress
            return
        }

        $allApps = @($catalog.applications)
        $categories = if ($catalog.categories) { @($catalog.categories) } else { @(Get-CategoryList -Catalog $catalog) }

        Show-ScreenTransition -IsAdmin -Scrollable
        Show-AppHeader -Scrollable; Write-Host ""
        Write-Host "  [ 1] | Uygulama Katalogu  >  KATALOG MERKEZI (KATEGORILER)" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "="; Write-Host ""

        Write-Host "  KATEGORILER (KATALOGLAR)" -ForegroundColor Cyan
        Write-Host ("  " + ("-" * 64)) -ForegroundColor DarkCyan
        Write-Host ""

        $i = 1
        foreach ($cat in $categories) {
            $catApps = @($allApps | Where-Object { "$($_.Category)".ToLower() -eq "$($cat.id)".ToLower() })
            $numTag = "[$i]".PadRight(4)
            Write-Host "    $numTag " -ForegroundColor Magenta -NoNewline
            $catLabel = "$($cat.icon) $($cat.name)"
            Write-Host $catLabel.PadRight(38) -ForegroundColor White -NoNewline
            Write-Host " : $($catApps.Count) Program" -ForegroundColor DarkCyan
            $i++
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 64)) -ForegroundColor DarkCyan
        Write-Host "  KATALOG SECENEKLERI" -ForegroundColor Cyan
        Write-Host "    [T] | Tum Uygulamalari Listele (2 Sutunlu Genel Liste)" -ForegroundColor Magenta
        Write-Host "    [A] | Katalogda Uygulama Ara" -ForegroundColor Magenta
        Write-Host "    [D] | Dogrudan Uygulama Detay Karti Ac" -ForegroundColor Magenta
        Write-Host "    [I] | Katalog Istatistiklerini Goruntule" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "    [0] | Yonetici Paneline Don" -ForegroundColor Red
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Kategori Numarasi veya Secim [1-$($categories.Count) | T, A, D, I | 0=Geri]: " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host
        $choice = if ($null -ne $inp) { $inp.Trim().ToUpper() } else { "" }

        if ($choice -eq "ESC" -or $choice -eq "0" -or $choice -eq "00") {
            $exitCatalogSub = $true
        } elseif ($choice -match '^\d+$') {
            $idx = [int]$choice
            if ($idx -ge 1 -and $idx -le $categories.Count) {
                $selCat = $categories[$idx - 1]
                Show-AdminCategoryAppsView -Category $selCat -Catalog $catalog
            } else {
                Write-Host "  [HATA] Gecersiz kategori numarasi." -ForegroundColor Red; Start-Sleep -Milliseconds 800
            }
        } elseif ($choice -eq "T") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [ 1] | Uygulama Katalogu  >  Tum Uygulamalar (Genel Liste)" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Show-AppList -Catalog $catalog
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Katalog menusune donmek icin bir tusa basin..."
        } elseif ($choice -eq "A") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [ 1] | Uygulama Katalogu  >  Uygulama Ara" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Show-AppSearchResults -Catalog $catalog
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Katalog menusune donmek icin bir tusa basin..."
        } elseif ($choice -eq "D") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [ 1] | Uygulama Katalogu  >  Uygulama Detayi" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Show-AppDetail -Catalog $catalog
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Katalog menusune donmek icin bir tusa basin..."
        } elseif ($choice -eq "I") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [ 1] | Uygulama Katalogu  >  Katalog Istatistikleri" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Show-CatalogStats -Catalog $catalog
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Katalog menusune donmek icin bir tusa basin..."
        } else {
            Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Milliseconds 800
        }
    }
}

function Invoke-AdminOption02 {
    Write-LogInfo "Admin secimi: [2] Yeni Uygulama Ekle"
    Show-ScreenTransition -IsAdmin -Scrollable
    if (Get-Command "Invoke-AddApplication" -ErrorAction SilentlyContinue) {
        Invoke-AddApplication
    } else {
        Write-Host "  [HATA] Invoke-AddApplication fonksiyonu yuklenemedi." -ForegroundColor Red
        Wait-UserKeyPress
    }
}

function Invoke-AdminOption03 {
    Write-LogInfo "Admin secimi: [3] Uygulamayi Duzenle"
    Show-ScreenTransition -IsAdmin -Scrollable
    if (Get-Command "Invoke-EditApplication" -ErrorAction SilentlyContinue) {
        Invoke-EditApplication
    } else {
        Write-Host "  [HATA] Invoke-EditApplication fonksiyonu yuklenemedi." -ForegroundColor Red
        Wait-UserKeyPress
    }
}

function Invoke-AdminOption04 {
    Write-LogInfo "Admin secimi: [4] Uygulamayi Sil"
    Show-ScreenTransition -IsAdmin -Scrollable
    if (Get-Command "Invoke-DeleteApplication" -ErrorAction SilentlyContinue) {
        Invoke-DeleteApplication
    } else {
        Write-Host "  [HATA] Invoke-DeleteApplication fonksiyonu yuklenemedi." -ForegroundColor Red
        Wait-UserKeyPress
    }
}

function Invoke-AdminOption05 {
    Write-LogInfo "Admin secimi: [5] Kategori Yonetimi"
    Show-ScreenTransition -IsAdmin -Scrollable
    if (Get-Command "Invoke-CategoryManagement" -ErrorAction SilentlyContinue) {
        Invoke-CategoryManagement
    } else {
        Write-Host "  [HATA] Invoke-CategoryManagement fonksiyonu yuklenemedi." -ForegroundColor Red
        Wait-UserKeyPress
    }
}

function Invoke-AdminOption06 {
    Write-LogInfo "Admin secimi: [6] Profil Yonetimi"
    Show-ScreenTransition -IsAdmin -Scrollable
    if (Get-Command "Invoke-ProfileManagement" -ErrorAction SilentlyContinue) {
        Invoke-ProfileManagement
    } else {
        Write-Host "  [HATA] Invoke-ProfileManagement fonksiyonu yuklenemedi." -ForegroundColor Red
        Wait-UserKeyPress
    }
}

function Show-LogInConsole {
    param([Parameter(Mandatory)][string]$LogPath)
    if (-not (Test-Path $LogPath)) {
        Write-Host "  [HATA] Dosya bulunamadi: $LogPath" -ForegroundColor Red
        Wait-UserKeyPress
        return
    }
    $lines = Get-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines -or $lines.Count -eq 0) {
        Write-Host "  [BILGI] Log dosyasi bos." -ForegroundColor Yellow
        Wait-UserKeyPress
        return
    }

    $pageSize = 22
    $totalLines = $lines.Count
    $totalPages = [Math]::Max(1, [Math]::Ceiling($totalLines / $pageSize))
    $currentPage = 1

    Show-ScreenTransition -IsAdmin:$script:AdminMode -Scrollable
    while ($true) {
        Show-AppHeader -Scrollable; Write-Host ""
        $fileName = Split-Path $LogPath -Leaf
        Write-Host "  LOG: $fileName  (Sayfa $currentPage / $totalPages | Toplam $totalLines satir)" -ForegroundColor Cyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

        $startIndex = ($currentPage - 1) * $pageSize
        $endIndex = [Math]::Min($startIndex + $pageSize - 1, $totalLines - 1)

        for ($i = $startIndex; $i -le $endIndex; $i++) {
            $l = $lines[$i]
            $lineColor = [ConsoleColor]::White
            if ($l -like "*[ERROR]*" -or $l -like "*[KRITIK*") { $lineColor = [ConsoleColor]::Red }
            elseif ($l -like "*[WARN]*") { $lineColor = [ConsoleColor]::Yellow }
            elseif ($l -like "*[SUCCESS]*") { $lineColor = [ConsoleColor]::Green }
            elseif ($l -like "*[INFO]*") { $lineColor = [ConsoleColor]::DarkCyan }
            Write-Host $l -ForegroundColor $lineColor
        }

        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host "  [Sonraki: ENTER / N]  [Onceki: P]  [Basa: T]  [Sona: E]  [ESC/0: Cikis]: " -ForegroundColor Yellow -NoNewline
        $nav = Read-Host
        $nav = if ($null -ne $nav) { $nav.Trim().ToUpper() } else { "" }

        if ($nav -eq "ESC" -or $nav -eq "0" -or $nav -eq "Q") { break }
        elseif ($nav -eq "P" -or $nav -eq "B") {
            if ($currentPage -gt 1) { $currentPage-- }
        }
        elseif ($nav -eq "T") { $currentPage = 1 }
        elseif ($nav -eq "E") { $currentPage = $totalPages }
        else {
            if ($currentPage -lt $totalPages) { $currentPage++ }
            else { break }
        }
    }
}

function Search-LogsInConsole {
    param(
        [Parameter(Mandatory)][string]$Keyword,
        [Parameter(Mandatory)][System.IO.FileInfo[]]$Logs
    )
    Show-ScreenTransition -IsAdmin:$script:AdminMode -Scrollable
    Show-AppHeader -Scrollable; Write-Host ""
    Write-Host "  LOG ARAMA SONUCLARI: '$Keyword'" -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    $matchCount = 0
    $maxMatches = 30

    foreach ($lg in ($Logs | Select-Object -First 10)) {
        $lines = Get-Content -LiteralPath $lg.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($lines) {
            $foundInFile = @($lines | Where-Object { $_ -like "*$Keyword*" })
            if ($foundInFile.Count -gt 0) {
                Write-Host "  Dosya: $($lg.Name) ($($foundInFile.Count) eslesme)" -ForegroundColor Magenta
                foreach ($fl in ($foundInFile | Select-Object -First 5)) {
                    $c = if ($fl -like "*[ERROR]*") { [ConsoleColor]::Red } elseif ($fl -like "*[WARN]*") { [ConsoleColor]::Yellow } else { [ConsoleColor]::White }
                    Write-Host "    $fl" -ForegroundColor $c
                    $matchCount++
                    if ($matchCount -ge $maxMatches) { break }
                }
            }
        }
        if ($matchCount -ge $maxMatches) {
            Write-Host "  ... [Daha fazla eslesme var, ilk $maxMatches kayit gosterildi] ..." -ForegroundColor Yellow
            break
        }
    }

    if ($matchCount -eq 0) {
        Write-Host "  '$Keyword' icin hicbir log kaydi bulunamadi." -ForegroundColor Yellow
    }
    Write-Host ""
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Wait-UserKeyPress -PromptMessage "Log menusune donmek icin bir tusa basin..."
}

function Invoke-AdminOption07 {
    Write-LogInfo "Admin secimi: [7] Log Dosyalarini Goruntule"
    $exitLogViewer = $false
    while (-not $exitLogViewer) {
        Show-ScreenTransition -IsAdmin
        Show-AppHeader; Write-Host ""
        Write-Host "  AAU YONETICI PANELI  >  [7] Log Dosyalarini Goruntule (Konsol Okuyucu)" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""

        $allLogs = @(Get-ChildItem -Path $script:LogsDir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        Write-Host "  Log Klasoru       : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:LogsDir" -ForegroundColor White
        Write-Host "  Toplam Log Sayisi : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$($allLogs.Count) adet" -ForegroundColor White
        Write-Host "  Aktif Oturum Logu : " -ForegroundColor DarkCyan -NoNewline
        if ($script:LogFilePath) { Write-Host (Split-Path $script:LogFilePath -Leaf) -ForegroundColor Green } else { Write-Host "Yok" -ForegroundColor Red }
        Write-Host ""

        if ($allLogs.Count -gt 0) {
            Write-Host "  Son Log Dosyalari:" -ForegroundColor Cyan
            $displayCount = [Math]::Min(8, $allLogs.Count)
            for ($i = 0; $i -lt $displayCount; $i++) {
                $lg = $allLogs[$i]
                $sz = if ($lg.Length -ge 1MB) { "{0:N2} MB" -f ($lg.Length / 1MB) } elseif ($lg.Length -ge 1KB) { "{0:N2} KB" -f ($lg.Length / 1KB) } else { "$($lg.Length) B" }
                $numTag = if (($i + 1) -lt 10) { "[ $($i + 1)]" } else { "[$($i + 1)]" }
                $activeTag = if ($lg.FullName -eq $script:LogFilePath) { " [AKTIF OTURUM]" } else { "" }
                Write-Host "    $numTag " -ForegroundColor Magenta -NoNewline
                Write-Host "$($lg.Name.PadRight(28))" -ForegroundColor White -NoNewline
                Write-Host " ($sz - $($lg.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))$activeTag" -ForegroundColor DarkCyan
            }
        } else {
            Write-Host "  Henuz olusturulmus log dosyasi bulunmuyor." -ForegroundColor Yellow
        }

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host "  [A] Aktif Oturum Logunu Konsolda Oku" -ForegroundColor Magenta
        Write-Host "  [S] Secilen Log Dosyasini Konsolda Oku (1-$($allLogs.Count))" -ForegroundColor Magenta
        Write-Host "  [F] Log Icerisinde Kelime Ara (Filtrele)" -ForegroundColor Magenta
        Write-Host "  [0] Geri Don" -ForegroundColor Red
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        $inp = Read-MenuInput -Prompt "  Seciminiz [A/S/F/0]: "
        $opt = if ($null -ne $inp) { $inp.Trim().ToUpper() } else { "" }

        switch ($opt) {
            "A" {
                if ($script:LogFilePath -and (Test-Path $script:LogFilePath)) {
                    Show-LogInConsole -LogPath $script:LogFilePath
                } else {
                    Write-Host "  [HATA] Aktif oturum log dosyasi bulunamadi." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }
            "S" {
                if ($allLogs.Count -gt 0) {
                    Write-Host "  Goruntulemek istediginiz log numarasi [1-$($allLogs.Count)]: " -ForegroundColor Yellow -NoNewline
                    $logNumStr = Read-Host
                    $logNum = 0
                    if ([int]::TryParse($logNumStr, [ref]$logNum) -and $logNum -ge 1 -and $logNum -le $allLogs.Count) {
                        $selectedLog = $allLogs[$logNum - 1]
                        Show-LogInConsole -LogPath $selectedLog.FullName
                    } else {
                        Write-Host "  [HATA] Gecersiz log numarasi." -ForegroundColor Red
                        Start-Sleep -Seconds 1
                    }
                }
            }
            "F" {
                if ($allLogs.Count -gt 0) {
                    Write-Host "  Aranacak kelime (Orn: ERROR, WARN, SUCCESS, Katalog): " -ForegroundColor Yellow -NoNewline
                    $kw = Read-Host
                    if ($kw -and $kw.Trim().Length -gt 0) {
                        Search-LogsInConsole -Keyword $kw.Trim() -Logs $allLogs
                    }
                }
            }
            "0" { $exitLogViewer = $true }
            default {
                Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Invoke-AdminOption08 {
    Write-LogInfo "Admin secimi: [8] Eski Loglari Sil"
    Show-LogCleanupMenu
}

function Invoke-AdminOption09 {
    Write-LogInfo "Admin secimi: [9] Kurulum Ayarlari"
    Show-ScreenTransition -IsAdmin -Scrollable
    if (Get-Command "Invoke-SettingsManagement" -ErrorAction SilentlyContinue) {
        Invoke-SettingsManagement
    } else {
        Write-Host "  [HATA] Invoke-SettingsManagement fonksiyonu yuklenemedi." -ForegroundColor Red
        Wait-UserKeyPress
    }
}

function Invoke-AdminOption10 {
    Write-LogInfo "Admin secimi: [10] Yedekleme ve Geri Yukleme"
    Show-ScreenTransition -IsAdmin -Scrollable
    if (Get-Command "Invoke-BackupManagement" -ErrorAction SilentlyContinue) {
        Invoke-BackupManagement
    } else {
        Write-Host "  [HATA] Invoke-BackupManagement fonksiyonu yuklenemedi." -ForegroundColor Red
        Wait-UserKeyPress
    }
}

function Invoke-AdminOption11 {
    Write-LogInfo "Admin secimi: [11] Modul Durumu Raporu"
    $exitModSub = $false
    while (-not $exitModSub) {
        $menuItems = @(
            "Tum Modulleri ve Durumlarini Listele",
            "Sistem ve Calisma Ortami Bilgisi",
            "Veri Dosyalari ve Katalog Butunluk Durumu",
            "WinGet ve Paket Kaynaklari Durumu",
            "Modul Sistemini Yeniden Baslat (Reload)"
        )
        Show-ScreenTransition -IsAdmin
        Show-AppHeader; Write-Host ""
        Write-Host "  [11] | Modul Durumu ve Sistem Raporu" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $menuItems) {
            Write-Host "  [ $i] |" -ForegroundColor Magenta -NoNewline
            Write-Host " $item" -ForegroundColor Magenta
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Yonetici Paneline Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitModSub = $true
        } elseif ($ch -eq "1") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [11] Modul Durumu  >  [1] Modul Listesi" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
            Write-Host "  Modul Klasoru  : $script:ModulesDir" -ForegroundColor DarkCyan
            Write-Host "  Yuklu Moduller : $($script:LoadedModules.Count) adet" -ForegroundColor White
            Write-Host ""
            if (Test-Path $script:ModulesDir) {
                $modFiles = Get-ChildItem -Path $script:ModulesDir -Recurse -File | Where-Object { $_.Extension -in ".psm1",".ps1" }
                foreach ($mf in $modFiles) {
                    $isLoaded = $script:LoadedModules -contains $mf.Name
                    $statusText = if ($isLoaded) { "[YUKLENDI]" } else { "[BEKLIYOR]" }
                    $statusColor = if ($isLoaded) { "Green" } else { "Yellow" }
                    $rel = $mf.FullName.Replace($script:ProjectRoot, "").TrimStart("\")
                    Write-Host "  $statusText " -ForegroundColor $statusColor -NoNewline
                    $szFmt = "{0:N1} KB" -f ($mf.Length / 1KB)
                    Write-Host "$rel ($szFmt)" -ForegroundColor White
                }
            }
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Modul menusune donmek icin bir tusa basin..."
        } elseif ($ch -eq "2") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [11] Modul Durumu  >  [2] Sistem ve Calisma Ortami Bilgisi" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
            Write-Host "  Isletim Sistemi     : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:OSName" -ForegroundColor White
            Write-Host "  Mimari              : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:OSArch" -ForegroundColor White
            Write-Host "  PowerShell Surumu   : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$($PSVersionTable.PSVersion.ToString())" -ForegroundColor White
            Write-Host "  Yonetici Yetkisi    : " -ForegroundColor DarkCyan -NoNewline
            if (Test-IsAdmin) { Write-Host "[EVET] Yonetici Haklari Aktif" -ForegroundColor Green } else { Write-Host "[HAYIR] Standart Kullanici" -ForegroundColor Yellow }
            Write-Host "  Proje Kok Dizini    : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:ProjectRoot" -ForegroundColor White
            Write-Host "  Aktif Oturum Logu   : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:LogFilePath" -ForegroundColor White
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Modul menusune donmek icin bir tusa basin..."
        } elseif ($ch -eq "3") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [11] Modul Durumu  >  [3] Veri Dosyalari ve Katalog Butunluk Durumu" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
            $dataFiles = @(
                (Join-Path $script:DataDir "apps\apps.json"),
                (Join-Path $script:DataDir "profiles\profiles.json"),
                (Join-Path $script:ConfigDir "settings.json")
            )
            foreach ($df in $dataFiles) {
                $exists = Test-Path $df
                $rel = $df.Replace($script:ProjectRoot, "").TrimStart("\")
                if ($exists) {
                    $valid = $false
                    try {
                        $raw = [System.IO.File]::ReadAllText($df, [System.Text.Encoding]::UTF8)
                        $null = ConvertFrom-Json $raw
                        $valid = $true
                    } catch {}
                    $st = if ($valid) { "[GECERLI]" } else { "[BOZUK]" }
                    $sc = if ($valid) { "Green" } else { "Red" }
                    $fi = Get-Item $df
                    $szFmt = "{0:N1} KB" -f ($fi.Length / 1KB)
                    Write-Host "  $st " -ForegroundColor $sc -NoNewline
                    Write-Host "$rel ($szFmt)" -ForegroundColor White
                } else {
                    Write-Host "  [EKSIK]    " -ForegroundColor Red -NoNewline
                    Write-Host "$rel" -ForegroundColor White
                }
            }
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Modul menusune donmek icin bir tusa basin..."
        } elseif ($ch -eq "4") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [11] Modul Durumu  >  [4] WinGet ve Paket Kaynaklari Durumu" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
            if (Get-Command "Show-WinGetStatus" -ErrorAction SilentlyContinue) {
                Show-WinGetStatus
            } else {
                Write-Host "  [BILGI] WinGet denetim modulu yuklenemedi." -ForegroundColor Yellow
            }
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Modul menusune donmek icin bir tusa basin..."
        } elseif ($ch -eq "5") {
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [11] Modul Durumu  >  [5] Modul Sistemini Yeniden Baslat" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
            Initialize-ModuleSystem
            Write-Host "  [BASARILI] Modul sistemi basariyla yeniden yuklendi." -ForegroundColor Green
            Write-Host "  Yuklu moduller: $($script:LoadedModules.Count) adet" -ForegroundColor White
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Modul menusune donmek icin bir tusa basin..."
        } else {
            Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Milliseconds 800
        }
    }
}

function Invoke-AdminOption12 {
    Write-LogInfo "Admin secimi: [12] Proje Klasorunu Ac"
    $exitDirSub = $false
    while (-not $exitDirSub) {
        $menuItems = @(
            "Proje Kok Dizinini Ac (Windows Gezgini)",
            "Islem Gunlukleri Klasorunu Ac (logs)",
            "Uygulama Katalogu Klasorunu Ac (data\apps)",
            "Kurulum Profilleri Klasorunu Ac (data\profiles)",
            "Sistem Yedekleri Klasorunu Ac (data\backups)",
            "Yapilandirma Klasorunu Ac (config)"
        )
        Show-ScreenTransition -IsAdmin
        Show-AppHeader; Write-Host ""
        Write-Host "  [12] | Proje ve Dizin Yonetim Merkezi" -ForegroundColor Magenta
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $i = 1
        foreach ($item in $menuItems) {
            Write-Host "  [ $i] |" -ForegroundColor Magenta -NoNewline
            Write-Host " $item" -ForegroundColor Magenta
            $i++
        }
        Write-Host ""; Write-Host "  [ 0] | " -ForegroundColor Red -NoNewline
        Write-Host "Yonetici Paneline Don  [ESC]" -ForegroundColor Red
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
        $inp = Read-MenuInput
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") {
            $exitDirSub = $true
        } elseif ($ch -match "^[1-6]$") {
            $targetPath = switch ($ch) {
                "1" { $script:ProjectRoot }
                "2" { $script:LogsDir }
                "3" { Join-Path $script:DataDir "apps" }
                "4" { Join-Path $script:DataDir "profiles" }
                "5" { Join-Path $script:DataDir "backups" }
                "6" { $script:ConfigDir }
            }
            if (-not (Test-Path $targetPath)) {
                $null = New-Item -ItemType Directory -Path $targetPath -Force -ErrorAction SilentlyContinue
            }
            Show-ScreenTransition -IsAdmin -Scrollable
            Show-AppHeader -Scrollable; Write-Host ""
            Write-Host "  [12] Dizin Yonetimi  >  Hedef Klasor Aciliyor" -ForegroundColor Magenta
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
            Write-Host "  Hedef Yol: $targetPath" -ForegroundColor White
            try {
                Start-Process explorer.exe -ArgumentList "`"$targetPath`""
                Write-Host ""
                Write-Host "  [BASARILI] Windows Gezgini ile klasor acildi." -ForegroundColor Green
            } catch {
                Write-Host ""
                Write-Host "  [HATA] Klasor acilamadi: $($_.Exception.Message)" -ForegroundColor Red
            }
            Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Dizin menusune donmek icin bir tusa basin..."
        } else {
            Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Milliseconds 800
        }
    }
}

function Start-AdminPanelLoop {
    Write-LogInfo "Yonetici Paneli ana menu dongusune girildi."
    $exitAdmin = $false
    while (-not $exitAdmin) {
        Show-AdminMenu
        $inp = Read-MenuInput -Prompt "  Seciminiz [1-12 | 20=Hakkinda | 0=Cikis]: "
        $ch  = if ($null -ne $inp) { $inp.Trim() } else { "" }

        switch ($ch) {
            { $_ -eq "1"  -or $_ -eq "01" } { Invoke-AdminOption01 }
            { $_ -eq "2"  -or $_ -eq "02" } { Invoke-AdminOption02 }
            { $_ -eq "3"  -or $_ -eq "03" } { Invoke-AdminOption03 }
            { $_ -eq "4"  -or $_ -eq "04" } { Invoke-AdminOption04 }
            { $_ -eq "5"  -or $_ -eq "05" } { Invoke-AdminOption05 }
            { $_ -eq "6"  -or $_ -eq "06" } { Invoke-AdminOption06 }
            { $_ -eq "7"  -or $_ -eq "07" } { Invoke-AdminOption07 }
            { $_ -eq "8"  -or $_ -eq "08" } { Invoke-AdminOption08 }
            { $_ -eq "9"  -or $_ -eq "09" } { Invoke-AdminOption09 }
            "10" { Invoke-AdminOption10 }
            "11" { Invoke-AdminOption11 }
            "12" { Invoke-AdminOption12 }
            "13" {
                $script:AdminMode = $false
                Start-StandardUserLoop
                $script:AdminMode = $true
            }
            "20" { Show-AboutScreen }
            { $_ -eq "ESC" -or $_ -eq "0" -or $_ -eq "00" } {
                $exitAdmin = $true
                Write-LogInfo "Yonetici Paneli kapatildi."
                Show-ClosingAnimation -IsAdmin:$true
                exit 0
            }
            default {
                Write-LogWarn "Gecersiz yonetici secimi: '$ch'"
                Write-Host ""
                Write-Host "  [HATA] Gecersiz secim! 1-12 arasinda bir numara girin." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Invoke-Category19 {
    Write-LogInfo "Kategori secimi: [19] Windows & Office Lisanslama"
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable; Write-Host ""
    Write-Host "  [19] | Windows & Office Lisanslama (MAS - Microsoft Activation Scripts)" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
    Write-Host "  Bu sekme asagidaki PowerShell aktivasyon aracini calistirir:" -ForegroundColor White
    Write-Host "    irm https://get.activated.win | iex" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-IsAdmin)) {
        Write-Host "  [UYARI] Lisanslama islemi Yonetici (Administrator) yetkisi gerektirir." -ForegroundColor Yellow
        Write-Host ""
        $ans = Read-Host "  Yonetici olarak calistirilsin mi? (E=Evet / H=Iptal)"
        if ($ans -and $ans.Trim().ToUpper() -in @("E","EVET","Y","YES")) {
            Write-LogInfo "Lisanslama araci yonetici yetkisiyle baslatiliyor..."
            try {
                Start-Process "powershell.exe" -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command "irm https://get.activated.win | iex"' -Verb RunAs -ErrorAction Stop
                Write-Host "  [BILGI] Yonetici penceresi acildi." -ForegroundColor Green
            } catch {
                Write-Host "  [HATA] Yonetici penceresi acilamadi: $($_.Exception.Message)" -ForegroundColor Red
                Write-LogError "Lisanslama yonetici baslatma hatasi: $($_.Exception.Message)"
            }
        } else {
            Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor Yellow
        }
        Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Wait-UserKeyPress
        return
    }

    Write-Host "  [BILGI] Aktivasyon araci baslatiliyor..." -ForegroundColor Green
    Write-Host ""
    try {
        Invoke-Expression (Invoke-RestMethod -Uri "https://get.activated.win")
        Write-LogSuccess "Lisanslama komutu tamamlandi."
    } catch {
        Write-Host "  [HATA] Aktivasyon komutu calistirilamadi: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogError "Lisanslama komutu hatasi: $($_.Exception.Message)"
    }
    Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Wait-UserKeyPress
}

# ============================================================================
# HAKKINDA EKRANI
# ============================================================================

function Show-AboutScreen {
    Write-LogInfo "Hakkinda ekrani acildi."
    Show-ScreenTransition -IsAdmin:$script:AdminMode -Scrollable
    Show-AppHeader -Scrollable; Write-Host ""
    Write-Host "  PROJE BILGILERI VE SISTEM DETAYLARI" -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"; Write-Host ""
    Write-Host "  Proje Adi       : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:AppName" -ForegroundColor White
    Write-Host "  Protokol        : " -ForegroundColor DarkCyan -NoNewline; Write-Host "Defender Protokolu" -ForegroundColor Cyan
    Write-Host "  Gelistirici     : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:AppAuthor" -ForegroundColor White
    Write-Host "  Surum           : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$script:AppVersion (18 Standart Kategori)" -ForegroundColor Green
    Write-Host "  Hedef Sistemler : " -ForegroundColor DarkCyan -NoNewline; Write-Host "Windows 10 / Windows 11 (64-bit)" -ForegroundColor White
    Write-Host "  PowerShell      : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($PSVersionTable.PSVersion.ToString()) (PS 5.1 Tam Uyumlu)" -ForegroundColor White
    Write-Host "  Yetki Durumu    : " -ForegroundColor DarkCyan -NoNewline
    if ($script:AdminMode) {
        Write-Host "Yonetici Paneli (Administrator Modu)" -ForegroundColor Magenta
    } elseif ($script:IsAdmin) {
        Write-Host "Kullanici Paneli (Yonetici Yetkili - Elevated)" -ForegroundColor Green
    } else {
        Write-Host "Kullanici Paneli (Standart Yetki)" -ForegroundColor Cyan
    }
    Write-Host "  Proje Dizini    : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:ProjectRoot" -ForegroundColor White
    Write-Host "  Aktif Log       : " -ForegroundColor DarkCyan -NoNewline; Write-Host "$script:LogFilePath" -ForegroundColor White
    Write-Host "  Logo / Simge    : " -ForegroundColor DarkCyan -NoNewline
    if ($script:AdminMode) {
        Write-Host "assets\admin.ico (Yonetici Guvenlik Kalkani Entegre)" -ForegroundColor Green
    } else {
        Write-Host "assets\aau.ico (Masaustu ve Konsol Entegre)" -ForegroundColor Green
    }
    Write-Host "  Yuklu Moduller  : " -ForegroundColor DarkCyan -NoNewline
    if ($script:LoadedModules.Count -gt 0) { Write-Host ($script:LoadedModules -join ", ") -ForegroundColor White }
    else { Write-Host "0 modul (altyapi hazir, harici dosyalar bekleniyor)" -ForegroundColor White }
    Write-Host ""; Write-Host "  [GUVENLIK VE MIMARI ILKELERI]" -ForegroundColor Cyan
    Write-Host "  - Kullanici onayi olmaksizin sistem ayarlarini degistirmez." -ForegroundColor White
    Write-Host "  - Telemetri veya veri toplama icermez." -ForegroundColor White
    Write-Host "  - Tum kritik islemler logs/ klasorune kaydedilir." -ForegroundColor White
    Write-Host ""; Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Wait-UserKeyPress
}

# ============================================================================
# STANDART KULLANICI DONGUSU (1-18)
# ============================================================================

function Start-StandardUserLoop {
    Write-LogInfo "Standart Kullanici ana menu dongusune girildi."
    $exitRequested = $false
    while (-not $exitRequested) {
        Show-MainMenu

        $inputChoice = Read-MenuInput -Prompt "  Seciminiz [1-22 | 0=Cikis]: "
        $choice = if ($null -ne $inputChoice) { $inputChoice.Trim() } else { "" }

        switch ($choice) {
            { $_ -eq "1"  -or $_ -eq "01" } { Invoke-Category01 }
            { $_ -eq "2"  -or $_ -eq "02" } { Invoke-Category02 }
            { $_ -eq "3"  -or $_ -eq "03" } { Invoke-Category03 }
            { $_ -eq "4"  -or $_ -eq "04" } { Invoke-Category04 }
            { $_ -eq "5"  -or $_ -eq "05" } { Invoke-Category05 }
            { $_ -eq "6"  -or $_ -eq "06" } { Invoke-Category16 }
            { $_ -eq "7"  -or $_ -eq "07" } { Invoke-Category07 }
            { $_ -eq "8"  -or $_ -eq "08" } { Invoke-Category08 }
            { $_ -eq "9"  -or $_ -eq "09" } { Invoke-Category09 }
            "10"  { Invoke-Category10 }
            "11"  { Invoke-Category11 }
            "12"  { Invoke-Category12 }
            "13"  { Invoke-Category13 }
            "14"  { Invoke-Category14 }
            "15"  { Invoke-Category15 }
            "16"  { Invoke-Category06 }
            "17"  { Invoke-Category17 }
            "18"  { Invoke-Category18 }
            { $_ -eq "19" -or $_ -eq "019" } { Invoke-Category19 }
            "20"  { Show-AboutScreen }
            "21"  { Invoke-PostFormatWizard }
            "22"  { Show-DebloatPrivacyMenu }
            { $_ -eq "ESC" -or $_ -eq "0" -or $_ -eq "00" } {
                $exitRequested = $true
                Write-LogInfo "Kullanici cikis yapti."
                Show-ClosingAnimation -IsAdmin:$false
                exit 0
            }
            default {
                Write-LogWarn "Gecersiz menu girisi: '$choice'"
                Write-Host ""
                Write-Host "  [HATA] Gecersiz secim! Listeden bir numara girin." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ============================================================================
# ANA CALISMA DONGUSU
# ============================================================================

function Ensure-AdminPrivileges {
    if ($env:AAU_SKIP_ELEVATION -eq "1") { return }
    if (-not [Environment]::UserInteractive) { return }
    if (-not (Test-IsAdmin)) {
        Write-Host ""
        Write-Host "  [BILGI] AAU Kurulum Asistani yonetici yetkileri ile baslatiliyor..." -ForegroundColor Yellow
        $scriptPath = if ($PSScriptRoot) { Join-Path $PSScriptRoot "main.ps1" } else { "src\main.ps1" }
        $argList = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($script:AdminMode) { $argList += " -AdminMode" }
        try {
            Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
            exit 0
        } catch {
            Write-Host "  [UYARI] Yonetici izni onaylanmadi; mevcut yetkiyle devam ediliyor." -ForegroundColor DarkGray
        }
    }
}

function Start-Application {
    try {
        Ensure-AdminPrivileges
        $script:IsAdmin = Test-IsAdmin
        Get-SystemInfoSummary
        Initialize-Logger
        Invoke-AutoLogCleanup
        Initialize-ModuleSystem

        # Ozel HEX renk paletini konsola uygula
        Set-ConsoleThemePalette

        # Konsol penceresini monitorde ortala ve logoyu simge olarak ata
        Set-ConsoleCentered
        Set-ConsoleAppIcon

        # Buyuk ASCII Acilis Animasyonu
        Show-OpeningAnimation -IsAdmin:$script:AdminMode

        # Baslik satirini ve ana donguyu calisma moduna gore ayarla
        if ($script:AdminMode) {
            $host.UI.RawUI.WindowTitle = "AAU Kurulum Asistani - Yonetici Paneli"
            Write-LogInfo "ADMIN MODU aktif - Yonetici Paneli baslatildi."
            Start-AdminPanelLoop
        } else {
            $host.UI.RawUI.WindowTitle = "AAU Kurulum Asistani"
            Write-LogInfo "STANDART KULLANICI MODU aktif - 18 kategori ana menu dongusune girildi."
            Start-StandardUserLoop
        }
    } catch {
        $err = $_.Exception.Message
        Write-LogError "Kritik hata: $err"
        Write-Host ""; Write-Host "  [KRITIK HATA] $err" -ForegroundColor Red
        Wait-UserKeyPress -PromptMessage "Cikis icin bir tusa basin..."
    }
}

# ============================================================================
# PROGRAMI BASLAT
# ============================================================================
Start-Application
