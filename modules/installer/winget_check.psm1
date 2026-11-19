<#
.SYNOPSIS
    AAU Kurulum Asistani - WinGet Kontrol Modulu
.DESCRIPTION
    WinGet yuklu mu kontrol eder, surum bilgisini alir, paket
    kaynaklarini ve internet baglantisini denetler. Kaynak yenileme ve
    sifirlama fonksiyonlari sunar.
.NOTES
    PowerShell 5.1 uyumlu.
#>

# ============================================================================
# YARDIMCI - Loglama yedek stub
# ============================================================================
if (-not (Get-Command "Write-LogInfo" -ErrorAction SilentlyContinue)) {
    function Write-LogInfo    { param([string]$m) }
    function Write-LogWarn    { param([string]$m) }
    function Write-LogError   { param([string]$m) }
    function Write-LogSuccess { param([string]$m) }
}

# ============================================================================
# TEST-WINGETAVAILABLE
# ============================================================================
function Test-WinGetAvailable {
<#
.SYNOPSIS
    WinGet komut satirinin kullanilabilir olup olmadigini dondurur.
.OUTPUTS
    [bool] $true / $false
#>
    try {
        $exe = Get-Command "winget.exe" -ErrorAction SilentlyContinue
        if (-not $exe) {
            Write-LogWarn "WinGet bulunamadi (Get-Command)."
            return $false
        }
        $null = & winget.exe --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-LogWarn "WinGet bulundu ancak --version basarisiz (ExitCode: $LASTEXITCODE)."
            return $false
        }
        Write-LogInfo "WinGet kullanilabilir."
        return $true
    } catch {
        Write-LogError "WinGet kontrol hatasi: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# GET-WINGETINFO
# ============================================================================
function Get-WinGetInfo {
<#
.SYNOPSIS
    WinGet hakkinda kapsamli durum ve kaynak bilgilerini dondurur.
.OUTPUTS
    [hashtable]
#>
    $info = @{
        IsAvailable        = $false
        Version            = "Bilgi alinamadi"
        Path               = "Bilgi alinamadi"
        Sources            = @()
        HasWingetSource    = $false
        HasMsStoreSource   = $false
        AppInstallerStatus = "Bilgi alinamadi"
        InternetAvailable  = $false
    }

    # Internet kontrolu
    try {
        $info.InternetAvailable = Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet -ErrorAction Stop
    } catch {
        try {
            $null = [System.Net.Dns]::GetHostAddresses("www.microsoft.com")
            $info.InternetAvailable = $true
        } catch {
            $info.InternetAvailable = $false
        }
    }

    try {
        # 1. winget.exe konum kontrolu
        $exe = Get-Command "winget.exe" -ErrorAction SilentlyContinue
        if (-not $exe) {
            $info.AppInstallerStatus = "WinGet bulunamadi"
            Write-LogWarn "WinGet sisteme yuklu degil."
            return $info
        }
        $info.Path = $exe.Source

        # 2. Surum bilgisi
        $ver = & winget.exe --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $ver) {
            $info.Version = ($ver | Out-String).Trim()
            $info.IsAvailable = $true
        } else {
            $info.AppInstallerStatus = "winget.exe calistirildi ancak surum alinamadi."
            return $info
        }

        # 3. App Installer bilesenini kontrol et
        try {
            $appx = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
            if ($appx) {
                $info.AppInstallerStatus = "Yuklu (Surum: $($appx.Version))"
            } else {
                $info.AppInstallerStatus = "App Installer paketi bulunamadi."
            }
        } catch {
            $info.AppInstallerStatus = "Kontrol edilemedi"
        }

        # 4. Kaynak listesi
        try {
            $srcLines = & winget.exe source list 2>$null
            if ($LASTEXITCODE -eq 0 -and $srcLines) {
                $parsed = @()
                $started = $false
                foreach ($line in $srcLines) {
                    $l = $line.Trim()
                    if (-not $l) { continue }
                    if ($l -match '^-+') { $started = $true; continue }
                    if ($started -and $l.Length -gt 2) {
                        $parts = $l -split '\s{2,}'
                        if ($parts.Count -ge 2) {
                            $srcObj = [PSCustomObject]@{
                                Name = $parts[0].Trim()
                                Url  = $parts[1].Trim()
                            }
                            $parsed += $srcObj
                            if ($srcObj.Name -ieq "winget") { $info.HasWingetSource = $true }
                            if ($srcObj.Name -ieq "msstore") { $info.HasMsStoreSource = $true }
                        }
                    }
                }
                $info.Sources = $parsed
            }
        } catch {
            Write-LogWarn "WinGet kaynak listesi alinamadi."
        }

        Write-LogSuccess "WinGet bilgileri basariyla alindi (Surum: $($info.Version))."
    } catch {
        Write-LogError "WinGet bilgi toplama hatasi: $($_.Exception.Message)"
    }

    return $info
}

# ============================================================================
# SHOW-WINGETSTATUS
# ============================================================================
function Show-WinGetStatus {
<#
.SYNOPSIS
    WinGet durum bilgilerini konsola gosterir ve interaktif kaynak yenileme sunar.
#>
    Write-LogInfo "WinGet durum kontrolu baslatildi."

    Write-Host ""
    Write-Host "  WINGET VE PAKET KAYNAKLARI KONTROLU" -ForegroundColor Green
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""

    $info = Get-WinGetInfo

    if (-not $info.IsAvailable) {
        Show-WinGetNotFoundMessage
        return
    }

    # Internet durumu
    Write-Host "    Internet Baglantisi: " -ForegroundColor DarkCyan -NoNewline
    if ($info.InternetAvailable) {
        Write-Host "Aktif (Baglanti Basarili)" -ForegroundColor Green
    } else {
        Write-Host "Baglanti Yok veya Sinirli" -ForegroundColor Red
    }

    # WinGet durumu
    Write-Host "    WinGet Durumu      : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "Kullanilabilir (Hazir)" -ForegroundColor Green

    # Surum
    Write-Host "    WinGet Surumu      : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($info.Version)" -ForegroundColor White

    # Konum
    Write-Host "    Uygulama Konumu    : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($info.Path)" -ForegroundColor White

    # App Installer
    Write-Host "    App Installer      : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($info.AppInstallerStatus)" -ForegroundColor White

    # Kaynaklar
    Write-Host ""
    Write-Host "    Kullanilabilir Paket Kaynaklari:" -ForegroundColor DarkCyan
    if ($info.Sources -and $info.Sources.Count -gt 0) {
        foreach ($src in $info.Sources) {
            $isStore = ($src.Name -ieq "msstore")
            $color = if ($isStore) { [ConsoleColor]::Cyan } else { [ConsoleColor]::Green }
            Write-Host "      [+] " -ForegroundColor $color -NoNewline
            Write-Host "$($src.Name)".PadRight(10) -ForegroundColor White -NoNewline
            Write-Host " : $($src.Url)" -ForegroundColor DarkCyan
        }
    } else {
        Write-Host "      [!] Hicbir paket kaynagi tanimli degil!" -ForegroundColor Red
    }

    # Ozel Kaynak Kontrolleri
    Write-Host ""
    Write-Host "    Kaynak Dogrulama:" -ForegroundColor DarkCyan
    Write-Host "      - WinGet Topluluk Deposu : " -ForegroundColor DarkCyan -NoNewline
    if ($info.HasWingetSource) { Write-Host "Aktif" -ForegroundColor Green } else { Write-Host "Eksik" -ForegroundColor Red }

    Write-Host "      - Microsoft Store        : " -ForegroundColor DarkCyan -NoNewline
    if ($info.HasMsStoreSource) { Write-Host "Aktif" -ForegroundColor Green } else { Write-Host "Eksik" -ForegroundColor Red }

    # Komut testi
    Write-Host ""
    Write-Host "    Komut Satiri Testi : " -ForegroundColor DarkCyan -NoNewline
    try {
        $null = & winget.exe --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Basarili (winget.exe sorunsuz calisiyor)" -ForegroundColor Green
        } else {
            Write-Host "Basarisiz (ExitCode: $LASTEXITCODE)" -ForegroundColor Red
        }
    } catch {
        Write-Host "Basarisiz ($($_.Exception.Message))" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host "  ISLEMLER:" -ForegroundColor DarkCyan
    Write-Host "    [1] Paket Kaynaklarini Guncelle (winget source update)" -ForegroundColor Yellow
    Write-Host "    [2] Paket Kaynaklarini Sifirla (winget source reset --force)" -ForegroundColor Yellow
    Write-Host "    [0] Tamam / Menuye Don" -ForegroundColor White
    Write-Host ""
    Write-Host "  Seciminiz [1, 2 veya 0=Geri]: " -ForegroundColor Yellow -NoNewline
    $sChoice = Read-Host
    if ($sChoice -eq "1") {
        Write-Host ""
        Write-Host "  Paket kaynaklari guncelleniyor, lutfen bekleyin..." -ForegroundColor Yellow
        try {
            $null = & winget.exe source update 2>&1
            Write-Host "  [BASARILI] Paket kaynaklari basariyla guncellendi!" -ForegroundColor Green
            Write-LogSuccess "WinGet kaynaklari guncellendi."
        } catch {
            Write-Host "  [HATA] Kaynak guncelleme hatasi: $($_.Exception.Message)" -ForegroundColor Red
        }
    } elseif ($sChoice -eq "2") {
        Write-Host ""
        Write-Host "  Paket kaynaklari sifirlaniyor..." -ForegroundColor Yellow
        try {
            $null = & winget.exe source reset --force 2>&1
            Write-Host "  [BASARILI] Paket kaynaklari varsayilana sifirlandi!" -ForegroundColor Green
            Write-LogSuccess "WinGet kaynaklari sifirlandi."
        } catch {
            Write-Host "  [HATA] Kaynak sifirlama hatasi: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-LogSuccess "WinGet durum kontrolu tamamlandi."
}

# ============================================================================
# SHOW-WINGETNOTFOUNDMESSAGE
# ============================================================================
function Show-WinGetNotFoundMessage {
<#
.SYNOPSIS
    WinGet bulunamadiginda kullaniciya yonlendirme mesaji gosterir.
#>
    Write-LogWarn "WinGet bulunamadi - kullaniciya bilgi mesaji gosteriliyor."

    Write-Host ""
    Write-Host "    [!] WinGet Bu Sistemde Bulunamadi" -ForegroundColor Red
    Write-Host ""
    Write-Host "    WinGet (Windows Package Manager), Windows uzerinden" -ForegroundColor White
    Write-Host "    uygulama kurulumu yapabilmek icin gereklidir." -ForegroundColor White
    Write-Host ""
    Write-Host "    Kurulum Yontemleri:" -ForegroundColor Green
    Write-Host "      1. Microsoft Store'dan 'App Installer' uygulamasini" -ForegroundColor White
    Write-Host "         guncelleyin veya yukleyin." -ForegroundColor White
    Write-Host ""
    Write-Host "      2. GitHub uzerinden indirin:" -ForegroundColor White
    Write-Host "         https://github.com/microsoft/winget-cli/releases" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "      3. PowerShell ile yukleyin (Yonetici gerekli):" -ForegroundColor White
    Write-Host "         Add-AppxPackage -RegisterByFamilyName" -ForegroundColor DarkCyan
    Write-Host "         Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "    [BILGI] WinGet olmadan uygulama katalogu" -ForegroundColor DarkCyan
    Write-Host "            goruntulenebilir ancak kurulum yapilamaz." -ForegroundColor DarkCyan
    Write-Host ""
}

# ============================================================================
# MODUL DISA AKTARIM
# ============================================================================
Export-ModuleMember -Function @(
    'Test-WinGetAvailable',
    'Get-WinGetInfo',
    'Show-WinGetStatus',
    'Show-WinGetNotFoundMessage'
)
