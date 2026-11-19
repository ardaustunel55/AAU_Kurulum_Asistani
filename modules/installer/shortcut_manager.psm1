<#
.SYNOPSIS
    AAU Kurulum Asistani - Baslat Menusu Kisayol ve Calistirilabilir Dosya Yonetim Modulu
.DESCRIPTION
    Kurulum sonrasi programin gercek calistirilabilir dosyasini (.exe) ve
    Baslat Menusu kisayollarini (Ortak ProgramData ve Kullanici AppData) denetler.
    Eksik kisayollar icin guvenli .lnk olusturma ve explorer'i kapatmadan
    SHChangeNotify ile Baslat Menusu yenileme yetenegi sunar.
.NOTES
    PowerShell 5.1 uyumlu.
#>

# Loglama fonksiyonlari fallback
if (-not (Get-Command "Write-LogInfo" -ErrorAction SilentlyContinue)) {
    function Write-LogInfo    { param([string]$m) }
    function Write-LogWarn    { param([string]$m) }
    function Write-LogError   { param([string]$m) }
    function Write-LogSuccess { param([string]$m) }
}

# ============================================================================
# C# PINVOKE: SHChangeNotify (Explorer'i kapatmadan kabuk yenileme)
# ============================================================================
try {
    $shNotifyCode = @"
using System;
using System.Runtime.InteropServices;
public static class AauShellNotify {
    [DllImport("shell32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);

    public static void NotifyShellUpdate() {
        try {
            // SHCNE_ASSOCCHANGED = 0x08000000 (SHCNF_IDLIST = 0x0000)
            SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero);
            // SHCNE_UPDATEDIR = 0x00001000 (SHCNF_FLUSH = 0x1000, SHCNF_PATHW = 0x0005)
            SHChangeNotify(0x00001000, 0x0005, IntPtr.Zero, IntPtr.Zero);
        } catch {}
    }
}
"@
    Add-Type -TypeDefinition $shNotifyCode -ErrorAction SilentlyContinue
} catch {}

# ============================================================================
# GET-APPEXECUTABLEPATH (Gercek Calistirilabilir Dosyayi Guvenle Tespit Et)
# ============================================================================
function Get-AppExecutablePath {
<#
.SYNOPSIS
    Bir uygulamanin gercek calistirilabilir (.exe) dosyasini tespit eder.
.PARAMETER AppName
    Uygulama gorunen adi (orn: "Google Chrome", "WinRAR")
.PARAMETER PackageId
    WinGet paket kimligi veya Id (orn: "Google.Chrome", "RARLab.WinRAR")
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Name", "ProgramName")]
        [string]$AppName,
        [Alias("Id", "AppId", "winget_id")]
        [string]$PackageId = ""
    )

    $cleanName = $AppName.Trim()
    $candidateExes = [System.Collections.Generic.List[string]]::new()

    # 1. Windows App Paths Kayit Defterini Tara (En guvenilir konum)
    $appPathRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths"
    )
    foreach ($apRoot in $appPathRoots) {
        if (Test-Path $apRoot) {
            $subKeys = Get-ChildItem -Path $apRoot -ErrorAction SilentlyContinue
            foreach ($sk in $subKeys) {
                $exeName = $sk.PSChildName
                # Isim benzerligi kontrolu (orn: chrome.exe, firefox.exe, winrar.exe)
                $nameParts = $cleanName -split '\s+'
                $matchesName = $false
                foreach ($part in $nameParts) {
                    if ($part.Length -ge 3 -and $exeName -like "*$part*.exe") {
                        $matchesName = $true
                        break
                    }
                }
                if ($matchesName) {
                    try {
                        $pVal = (Get-ItemProperty -LiteralPath $sk.PSPath -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
                        if ($pVal) {
                            $cleanPVal = $pVal.Trim().Trim('"')
                            if ((Test-Path -LiteralPath $cleanPVal) -and $cleanPVal -like "*.exe") {
                                return $cleanPVal
                            }
                        }
                    } catch {}
                }
            }
        }
    }

    # 2. Windows Uninstall Kayitlarini Tara (DisplayIcon, InstallLocation, UninstallString)
    $uninstallRoots = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($unRoot in $uninstallRoots) {
        try {
            $items = Get-ItemProperty -Path $unRoot -ErrorAction SilentlyContinue
            foreach ($it in $items) {
                $dName = $it.DisplayName
                if (-not $dName) { continue }
                if ($dName -like "*$cleanName*" -or ($PackageId -and ($it.PSChildName -eq $PackageId -or $dName -like "*$PackageId*"))) {
                    # DisplayIcon kontrolu
                    if ($it.DisplayIcon) {
                        $iconRaw = $it.DisplayIcon.Trim().Trim('"')
                        # "C:\Path\app.exe,0" formatindaki virgullu kismi temizle
                        if ($iconRaw -match '^([^,]+)(,\d+)?$') {
                            $iconPath = $matches[1].Trim().Trim('"')
                            if ((Test-Path -LiteralPath $iconPath) -and $iconPath -like "*.exe") {
                                return $iconPath
                            }
                        }
                    }

                    # InstallLocation klasorunu tara
                    if ($it.InstallLocation -and (Test-Path -LiteralPath $it.InstallLocation)) {
                        $dirExes = Get-ChildItem -LiteralPath $it.InstallLocation -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                                   Where-Object { $_.Name -notmatch '(?i)unins|setup|update|helper|crash|installer' }
                        if ($dirExes -and $dirExes.Count -gt 0) {
                            # Uygulama adina en cok benzeyen exe'yi bul
                            $bestExe = $dirExes | Where-Object { $cleanName -like "*$($_.BaseName)*" -or $_.BaseName -like "*$cleanName*" } | Select-Object -First 1
                            if (-not $bestExe) { $bestExe = $dirExes | Sort-Object Length -Descending | Select-Object -First 1 }
                            if ($bestExe) { return $bestExe.FullName }
                        }
                    }

                    # UninstallString dizinini incele
                    if ($it.UninstallString) {
                        $unStr = $it.UninstallString.Trim().Trim('"')
                        if ($unStr -match '^"([^"]+)"') { $unStr = $matches[1] }
                        elseif ($unStr -match '^([A-Za-z]:\\[^\s]+\.exe)') { $unStr = $matches[1] }
                        if (Test-Path -LiteralPath $unStr) {
                            $parentDir = Split-Path -Parent $unStr
                            if ($parentDir -and (Test-Path -LiteralPath $parentDir)) {
                                $siblingExes = Get-ChildItem -LiteralPath $parentDir -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                                               Where-Object { $_.Name -notmatch '(?i)unins|setup|update|helper|crash|installer' }
                                if ($siblingExes -and $siblingExes.Count -gt 0) {
                                    $sBest = $siblingExes | Where-Object { $cleanName -like "*$($_.BaseName)*" } | Select-Object -First 1
                                    if ($sBest) { return $sBest.FullName }
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # 3. PATH Ortam Degiskenini Tara
    try {
        $shortWord = ($cleanName -split '\s+')[0]
        $cmd = Get-Command "$shortWord.exe" -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) {
            return $cmd.Source
        }
    } catch {}

    # 4. Standart Program Klasorlerini Tara
    $stdDirs = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        (Join-Path $env:LOCALAPPDATA "Programs")
    )
    foreach ($sDir in $stdDirs) {
        if (-not $sDir -or -not (Test-Path -LiteralPath $sDir)) { continue }
        $matchDirs = Get-ChildItem -LiteralPath $sDir -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -like "*$cleanName*" -or $cleanName -like "*$($_.Name)*" }
        foreach ($md in $matchDirs) {
            $exes = Get-ChildItem -LiteralPath $md.FullName -Filter "*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '(?i)unins|setup|update|helper|crash|installer' }
            if ($exes -and $exes.Count -gt 0) {
                $picked = $exes | Where-Object { $cleanName -like "*$($_.BaseName)*" } | Select-Object -First 1
                if (-not $picked) { $picked = $exes | Sort-Object Length -Descending | Select-Object -First 1 }
                if ($picked) { return $picked.FullName }
            }
        }
    }

    return $null
}

# ============================================================================
# TEST-APPSTARTMENUSHORTCUT (Baslat Menusu Kisayol ve Kayit Denetimi)
# ============================================================================
function Test-AppStartMenuShortcut {
<#
.SYNOPSIS
    Bir uygulamanin Baslat Menusunde yer alip almadigini (Ortak, Kullanici ve AppX) denetler.
.OUTPUTS
    [hashtable]
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Name", "ProgramName")]
        [string]$AppName,
        [Alias("Id", "AppId", "winget_id")]
        [string]$PackageId = "",
        [Alias("ExePath")]
        [string]$KnownExePath = ""
    )

    $result = @{
        AppName          = $AppName
        PackageId        = $PackageId
        ExeFound         = $false
        ExePath          = ""
        ShortcutFound    = $false
        ShortcutPath     = ""
        ShortcutLocation = ""
        ShortcutType     = "None" # Lnk, AppX, None
        IsReady          = $false
    }

    # 1. Calistirilabilir Dosyayi Belirle
    $exePath = if ($KnownExePath -and (Test-Path -LiteralPath $KnownExePath)) { $KnownExePath }
               else { Get-AppExecutablePath -AppName $AppName -PackageId $PackageId }

    if ($exePath) {
        $result.ExeFound = $true
        $result.ExePath  = $exePath
    }

    # 2. Modern AppX / MSIX Uygulama Kaydini Denetle
    try {
        $cleanWord = ($AppName -split '\s+')[0]
        $appx = Get-AppxPackage -Name "*$cleanWord*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($appx -and $appx.Status -eq "Ok") {
            $result.ShortcutFound    = $true
            $result.ShortcutType     = "AppX"
            $result.ShortcutLocation = "Windows Modern Uygulama Kaydi (AppX/MSIX: $($appx.Name))"
            $result.IsReady          = $true
            return $result
        }
    } catch {}

    # 3. Baslat Menusu Klasorlerini Tara
    # Ortak: C:\ProgramData\Microsoft\Windows\Start Menu\Programs
    # Kullanici: %APPDATA%\Microsoft\Windows\Start Menu\Programs
    $commonMenu = [System.Environment]::GetFolderPath('CommonPrograms')
    $userMenu   = [System.Environment]::GetFolderPath('Programs')

    $menuDirs = @(
        @{ Path = $commonMenu; Label = "Ortak (ProgramData)" },
        @{ Path = $userMenu;   Label = "Kullanici (AppData)" }
    )

    $wsh = $null
    try {
        $wsh = New-Object -ComObject WScript.Shell
    } catch {}

    $searchKeywords = [System.Collections.Generic.List[string]]::new()
    $searchKeywords.Add($AppName.Trim().ToLower())
    $parts = $AppName -split '\s+'
    if ($parts.Count -gt 1) {
        foreach ($p in $parts) {
            if ($p.Length -ge 4) { $searchKeywords.Add($p.ToLower()) }
        }
    }

    foreach ($md in $menuDirs) {
        if (-not $md.Path -or -not (Test-Path -LiteralPath $md.Path)) { continue }

        $lnkFiles = Get-ChildItem -LiteralPath $md.Path -Filter "*.lnk" -Recurse -File -ErrorAction SilentlyContinue
        foreach ($lnk in $lnkFiles) {
            $baseLower = $lnk.BaseName.ToLower()

            # Isim tam veya alt metin eslesmesi
            $nameMatched = $false
            if ($baseLower -eq $AppName.Trim().ToLower()) {
                $nameMatched = $true
            } else {
                foreach ($kw in $searchKeywords) {
                    if ($baseLower.Contains($kw)) {
                        $nameMatched = $true
                        break
                    }
                }
            }

            # Hedef exe eslesmesi (WScript.Shell ile dogrulama)
            $targetMatched = $false
            if ($wsh -and $exePath) {
                try {
                    $sc = $wsh.CreateShortcut($lnk.FullName)
                    if ($sc.TargetPath) {
                        $targetClean = $sc.TargetPath.Trim().Trim('"').ToLower()
                        if ($targetClean -eq $exePath.ToLower()) {
                            $targetMatched = $true
                        }
                    }
                } catch {}
            }

            if ($nameMatched -or $targetMatched) {
                $result.ShortcutFound    = $true
                $result.ShortcutPath     = $lnk.FullName
                $result.ShortcutLocation = "$($md.Label): $($lnk.Name)"
                $result.ShortcutType     = "Lnk"
                $result.IsReady          = $true

                if ($wsh) {
                    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null } catch {}
                }
                return $result
            }
        }
    }

    if ($wsh) {
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null } catch {}
    }

    $result.IsReady = ($result.ExeFound -and $result.ShortcutFound)
    return $result
}

# ============================================================================
# INVOKE-CREATEAPPSHORTCUT (Guvenli Baslat Menusu Kisayolu Olusturma)
# ============================================================================
function Invoke-CreateAppShortcut {
<#
.SYNOPSIS
    Belirtilen program icin kullanici Baslat Menusu klasorunde guvenli bir kisayol (.lnk) olusturur.
    Oncelikli olarak kullanici klasorunu (%APPDATA%\Microsoft\Windows\Start Menu\Programs) kullanir.
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Name", "ProgramName")]
        [string]$AppName,
        [Parameter(Mandatory)]
        [Alias("Path", "ExecutablePath")]
        [string]$ExePath,
        [string]$ShortcutName = ""
    )

    if (-not (Test-Path -LiteralPath $ExePath)) {
        Write-LogError "Kisayol olusturulamadi: EXE dosyasi bulunamadi ($ExePath)"
        return $false
    }

    # Kullanici Baslat Menusu klasoru (Yonetici yetkisi gerektirmez)
    $userProgramsDir = [System.Environment]::GetFolderPath('Programs')
    if (-not (Test-Path -LiteralPath $userProgramsDir)) {
        try {
            $null = New-Item -ItemType Directory -Path $userProgramsDir -Force
        } catch {
            Write-LogError "Baslat Menusu klasorune erisilemedi: $($_.Exception.Message)"
            return $false
        }
    }

    # Guvenli dosya adi
    $cleanName = if ($ShortcutName) { $ShortcutName.Trim() } else { $AppName.Trim() }
    # Gecersiz karakterleri temizle
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($c in $invalidChars) {
        $cleanName = $cleanName.Replace([string]$c, '')
    }
    if (-not $cleanName) { $cleanName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath) }

    $targetLnkPath = Join-Path $userProgramsDir "$cleanName.lnk"

    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($targetLnkPath)
        $shortcut.TargetPath       = $ExePath
        $shortcut.WorkingDirectory = Split-Path -Parent $ExePath
        $shortcut.IconLocation     = "$ExePath,0"
        $shortcut.Description      = "$AppName - AAU Kurulum Asistani tarafindan olusturuldu"
        $shortcut.Save()

        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null

        # Explorer'i kapatmadan Windows Shell'e yenileme bildirimi gonder
        try {
            [AauShellNotify]::NotifyShellUpdate()
        } catch {}

        Write-LogSuccess "Baslat Menusu kisayolu basariyla olusturuldu: $targetLnkPath"
        return $true
    } catch {
        Write-LogError "Kisayol olusturma hatasi: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# SHOW-POSTINSTALLSHORTCUTCHECK (Kurulum Sonrasi Etkilesimli Kontrol Ekrani)
# ============================================================================
function Show-PostInstallShortcutCheck {
<#
.SYNOPSIS
    Kurulum tamamlandiktan sonra programin dosya ve Baslat Menusu durumunu kontrol eder,
    kullaniciya raporlar ve eksikse etkilesimli cozum sunar.
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Name", "ProgramName")]
        [string]$AppName,
        [Alias("Id", "AppId", "winget_id")]
        [string]$PackageId = "",
        [Alias("ExePath")]
        [string]$KnownExePath = "",
        [switch]$SilentMode
    )

    Write-Host ""
    Write-Host "  Kurulum sonrasi kisayol ve dosya butunlugu kontrol ediliyor..." -ForegroundColor DarkCyan

    $check = Test-AppStartMenuShortcut -AppName $AppName -PackageId $PackageId -KnownExePath $KnownExePath

    # Eger sessiz moddaysa (toplu kurulum sirasinda hizli gecis)
    if ($SilentMode) {
        if ($check.ShortcutFound) {
            Write-Host "  [✓] Baslat Menusu: $($check.ShortcutLocation)" -ForegroundColor Green
            return $check
        } elseif ($check.ExeFound) {
            # Sessiz modda da otomatik olarak kullanici baslat menusune kisayol ekle
            $created = Invoke-CreateAppShortcut -AppName $AppName -ExePath $check.ExePath
            if ($created) {
                Write-Host "  [✓] Baslat Menusu kisayolu otomatik olusturuldu." -ForegroundColor Green
            } else {
                Write-Host "  [!] Baslat Menusu kisayolu bulunamadi." -ForegroundColor Yellow
            }
            return $check
        } else {
            Write-Host "  [!] Program exe dosyasi otomatik tespit edilemedi." -ForegroundColor DarkCyan
            return $check
        }
    }

    # Etkilesimli Ekrani Ciz
    Write-Host ""
    Write-Host "  " + ("=" * 56) -ForegroundColor DarkCyan
    Write-Host "  KURULUM SONRASI KONTROL" -ForegroundColor White
    Write-Host "  " + ("-" * 56) -ForegroundColor DarkCyan
    Write-Host "  Program: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$AppName" -ForegroundColor White
    Write-Host ""

    Write-Host "  [✓] Kurulum dogrulandi." -ForegroundColor Green

    if ($check.ExeFound) {
        Write-Host "  [✓] Program dosyasi bulundu." -ForegroundColor Green
        Write-Host "      Konum: $($check.ExePath)" -ForegroundColor DarkGray
    } else {
        Write-Host "  [!] Program calistirilabilir (.exe) dosyasi henuz tespit edilemedi." -ForegroundColor Yellow
    }

    if ($check.ShortcutFound) {
        Write-Host "  [✓] Baslat menusu kisayolu bulundu." -ForegroundColor Green
        Write-Host "      Kayit: $($check.ShortcutLocation)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Durum: Hazir" -ForegroundColor Green
        Write-Host "  " + ("=" * 56) -ForegroundColor DarkCyan
        Start-Sleep -Milliseconds 800
        return $check
    } else {
        Write-Host "  [!] Baslat menusu kisayolu bulunamadi." -ForegroundColor Red
        Write-Host "  " + ("-" * 56) -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  [1] Kisayol Olusturmayi Dene" -ForegroundColor Green
        Write-Host "  [2] Program Konumunu Ac" -ForegroundColor Cyan
        Write-Host "  [3] Atla" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Seciminiz [1-3 | Varsayilan: 1]: " -ForegroundColor Yellow -NoNewline
        $ans = Read-Host
        $choice = if ($null -ne $ans -and $ans.Trim()) { $ans.Trim() } else { "1" }

        switch ($choice) {
            "1" {
                if ($check.ExeFound) {
                    $ok = Invoke-CreateAppShortcut -AppName $AppName -ExePath $check.ExePath
                    if ($ok) {
                        Write-Host ""
                        Write-Host "  [✓] Baslat Menusu kisayolu basariyla olusturuldu!" -ForegroundColor Green
                        Write-Host "  [BILGI] Windows Baslat Menusu guncellendi." -ForegroundColor DarkCyan
                        Start-Sleep -Seconds 1
                    } else {
                        Write-Host ""
                        Write-Host "  [HATA] Kisayol olusturulamadi." -ForegroundColor Red
                        Start-Sleep -Seconds 1
                    }
                } else {
                    Write-Host ""
                    Write-Host "  [UYARI] Program EXE dosyasi bulunamadigi icin hatali kisayol olusturulmadi." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }
            }
            "2" {
                if ($check.ExeFound) {
                    try {
                        Start-Process "explorer.exe" -ArgumentList "/select,`"$($check.ExePath)`""
                        Write-Host "  [BILGI] Program klasoru Dosya Gezgininde acildi." -ForegroundColor Green
                    } catch {
                        $pDir = Split-Path -Parent $check.ExePath
                        Start-Process "explorer.exe" -ArgumentList "`"$pDir`""
                    }
                    Start-Sleep -Milliseconds 500
                } else {
                    Write-Host "  [UYARI] Program konumu tespit edilemedi." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                }
            }
            "3" {
                Write-Host "  [BILGI] Kisayol denetimi atlandi." -ForegroundColor DarkCyan
                Start-Sleep -Milliseconds 400
            }
        }
        return $check
    }
}

Export-ModuleMember -Function @(
    'Get-AppExecutablePath',
    'Test-AppStartMenuShortcut',
    'Invoke-CreateAppShortcut',
    'Show-PostInstallShortcutCheck'
)
