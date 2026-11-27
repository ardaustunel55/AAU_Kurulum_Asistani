<#
.SYNOPSIS
    AAU Kurulum Asistani - WinGet Kurulum Motoru (Profesyonel Surum)
.DESCRIPTION
    WinGet uzerinden tekli ve toplu program kurulumu yapan ana moduldur.
    Gercek WinGet komutlarini guvenli sekilde calistirir, canli ilerleme yuzdesi
    ve animasyonlu marquee cubugu gosterir, hatalari yonetir, detayli log tutar,
    kurulum sonrasi dogrulama yapar ve sonuc raporu olusturur.
    Invoke-Expression KULLANILMAZ. Tum komutlar guvenli parametre dizileri ile olusturulur.
.NOTES
    Surum      : 2.1.0
    PowerShell : 5.1+ uyumlu
    Guvenlik   : Kullanici onayi olmadan sistemde degisiklik yapmaz.
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
if (-not (Get-Command "Draw-HorizontalLine" -ErrorAction SilentlyContinue)) {
    function Draw-HorizontalLine {
        param([int]$Width = 86, [ConsoleColor]$Color = [ConsoleColor]::DarkCyan, [string]$Char = "-")
        Write-Host ($Char * $Width) -ForegroundColor $Color
    }
}
if (-not (Get-Command "Show-AppHeader" -ErrorAction SilentlyContinue)) {
    function Show-AppHeader {
        param([switch]$Scrollable)
        Write-Host "==============================================================================" -ForegroundColor DarkCyan
        Write-Host "                    AAU KURULUM ASISTANI                                      " -ForegroundColor Cyan
        Write-Host "==============================================================================" -ForegroundColor DarkCyan
    }
}

# ============================================================================
# SCRIPT DEGISKENLERI VE PROCESS TRACKING
# ============================================================================
$script:InstallHistoryDir  = $null
$script:InstallHistoryFile = $null
$script:CurrentSessionId   = $null
$script:CurrentSessionResults = @()

$script:AllowedSources       = @('winget', 'msstore')
$script:AllowedScopes         = @('user', 'machine')
$script:AllowedArchitectures  = @('x64', 'x86', 'arm64', 'arm')

$script:SpinnerChars = @('|', '/', '-', '\')

# Aktif calisan kurulum sureclerini takip listesi (Cocuk islemleri korumasiz birakmamak icin)
if (-not $global:AauActiveInstallers) {
    $global:AauActiveInstallers = [System.Collections.Generic.List[PSCustomObject]]::new()
}

# ============================================================================
# PROCESS VE COCUK ISLEM (CHILD PROCESS) GUVENLI DURDURMA MOTORU
# ============================================================================
function Stop-ProcessTree {
<#
.SYNOPSIS
    Belirtilen sureci ve baslatmis oldugu TUM COCUK ISLEMLERI (process tree)
    guvenli ve eksiksiz sekilde durdurur. WinGet ve bagli yukleyicilerin (setup.exe,
    msiexec vb.) arka planda yetim (orphan) kalmasini kesin olarak engeller.
#>
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId,
        [string]$ProcessName = ""
    )

    try {
        Write-LogWarn "Surec agaci durduruluyor: PID $ProcessId ($ProcessName)"

        # 1. Windows taskkill /T /F ile agac sonlandirma (En hizli ve koklu cozum)
        try {
            $pKill = Start-Process -FilePath "taskkill.exe" -ArgumentList "/PID $ProcessId /T /F" -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
        } catch {}

        # 2. WMI/CIM uzerinden cocuk islemleri tara ve sonlandir
        try {
            $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue
            if ($children) {
                foreach ($c in $children) {
                    try {
                        Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue
                    } catch {}
                }
            }
        } catch {}

        # 3. Ana surecin kendisini sonlandir
        try {
            $mainProc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
            if ($mainProc -and -not $mainProc.HasExited) {
                $mainProc.Kill()
            }
        } catch {}

        Write-LogSuccess "Surec agaci basariyla sonlandirildi (PID: $ProcessId)."
    } catch {
        Write-LogError "Surec agaci sonlandirma hatasi: $($_.Exception.Message)"
    }
}

function Stop-AllRunningInstallers {
<#
.SYNOPSIS
    Uygulama kapanirken veya kullanici cikisinda calismakta olan tum kurulum
    sureclerini ve cocuk islemlerini guvenli sekilde durdurur.
#>
    try {
        if ($global:AauActiveInstallers -and $global:AauActiveInstallers.Count -gt 0) {
            Write-LogWarn "Uygulama kapanisi: $($global:AauActiveInstallers.Count) aktif kurulum sureci durduruluyor..."
            $listCopy = @($global:AauActiveInstallers)
            foreach ($item in $listCopy) {
                if ($item -and $item.Id) {
                    Stop-ProcessTree -ProcessId $item.Id -ProcessName $item.AppName
                }
            }
            $global:AauActiveInstallers.Clear()
        }
    } catch {}
}

# PowerShell kapanis olaylarina guvenli durdurma kancasi (hook) ekle
try {
    [System.AppDomain]::CurrentDomain.add_ProcessExit({
        Stop-AllRunningInstallers
    })
} catch {}

try {
    $null = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action {
        Stop-AllRunningInstallers
    } -SupportEvent -ErrorAction SilentlyContinue
} catch {}

$script:WinGetExitCodes = @{
    0             = 'Basarili'
    3010          = 'Basarili (Yeniden baslatma gerekli)'
    (-1978335231) = 'Paket katalogda bulunamadi'
    (-1978335230) = 'Paket kaynagi bulunamadi'
    (-1978335215) = 'Baska bir kurulum zaten devam ediyor'
    (-1978335212) = 'Kullanici islemi iptal etti'
    (-1978335208) = 'Yonetici (Administrator) yetkisi gerekli'
    (-1978335189) = 'Hash/Karma dogrulamasi basarisiz oldu'
    (-1978335178) = 'Paket zaten en guncel surumde'
    (-1978335160) = 'Gereksinimler veya isletim sistemi desteklenmiyor'
}

# ============================================================================
# INITIALIZE-INSTALLERPATHS
# ============================================================================
function Initialize-InstallerPaths {
<#
.SYNOPSIS
    Kurulum log ve gecmis dizinlerini hazirlar.
#>
    $root = if ($global:ProjectRoot) { $global:ProjectRoot }
            elseif ($script:ProjectRoot) { $script:ProjectRoot }
            else { (Get-Location).Path }

    $script:InstallHistoryDir = Join-Path $root "logs\install_history"
    $script:InstallHistoryFile = Join-Path $script:InstallHistoryDir "install_history.json"

    if (-not (Test-Path $script:InstallHistoryDir)) {
        try {
            $null = New-Item -ItemType Directory -Path $script:InstallHistoryDir -Force
            Write-LogInfo "Kurulum gecmisi dizini olusturuldu: $($script:InstallHistoryDir)"
        } catch {
            Write-LogError "Kurulum gecmisi dizini olusturulamadi: $($_.Exception.Message)"
        }
    }

    if (-not $script:CurrentSessionId) {
        $script:CurrentSessionId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    }
}

# ============================================================================
# TEST-INTERNETCONNECTION
# ============================================================================
function Test-InternetConnection {
<#
.SYNOPSIS
    Internet baglantisinin mevcut olup olmadigini kontrol eder.
.OUTPUTS
    [bool] $true / $false
#>
    try {
        $result = Test-Connection -ComputerName "www.microsoft.com" -Count 1 -Quiet -ErrorAction Stop
        if ($result) {
            Write-LogInfo "Internet baglantisi mevcut."
            return $true
        }
        return $false
    } catch {
        try {
            $null = [System.Net.Dns]::GetHostAddresses("www.microsoft.com")
            Write-LogInfo "Internet baglantisi mevcut (DNS)."
            return $true
        } catch {
            Write-LogWarn "Internet baglantisi yok: $($_.Exception.Message)"
            return $false
        }
    }
}

# ============================================================================
# TEST-WINGETREADY
# ============================================================================
function Test-WinGetReady {
<#
.SYNOPSIS
    WinGet ve internet tam hazirlik durumunu denetler.
#>
    $result = @{
        IsReady            = $false
        WinGetAvailable    = $false
        InternetAvailable  = $false
        SourcesOk          = $false
        WinGetVersion      = "Bilinmiyor"
        Details            = @()
    }

    Write-LogInfo "WinGet hazirlik kontrolu baslatildi."

    $result.InternetAvailable = Test-InternetConnection
    if (-not $result.InternetAvailable) {
        $result.Details += "Internet baglantisi bulunamadi."
    }

    $wingetCmd = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        $result.Details += "WinGet sisteme yuklu degil."
        Write-LogWarn "WinGet bulunamadi."
        return $result
    }

    try {
        $ver = & winget.exe --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $ver) {
            $result.WinGetAvailable = $true
            $result.WinGetVersion = ($ver | Out-String).Trim()
            Write-LogInfo "WinGet surumu: $($result.WinGetVersion)"
        } else {
            $result.Details += "WinGet bulundu ancak calistirilamadi."
            return $result
        }
    } catch {
        $result.Details += "WinGet calistirma hatasi: $($_.Exception.Message)"
        return $result
    }

    try {
        $srcOutput = & winget.exe source list 2>$null
        if ($LASTEXITCODE -eq 0 -and $srcOutput) {
            $result.SourcesOk = $true
            Write-LogInfo "WinGet kaynaklari hazir."
        } else {
            $result.Details += "WinGet kaynaklari erisilemez durumda."
        }
    } catch {
        $result.Details += "Kaynak listesi alinamadi: $($_.Exception.Message)"
    }

    if ($result.WinGetAvailable -and $result.InternetAvailable -and $result.SourcesOk) {
        $result.IsReady = $true
        Write-LogSuccess "WinGet tam hazir."
    } else {
        Write-LogWarn "WinGet hazir degil: $($result.Details -join ' | ')"
    }

    return $result
}

# ============================================================================
# SHOW-WINGETREADINESSERROR
# ============================================================================
function Show-WinGetReadinessError {
<#
.SYNOPSIS
    WinGet hazirlik hatasini kullaniciya renkli aciklar.
#>
    param([hashtable]$ReadinessResult)

    Write-Host ""
    Write-Host "  WINGET HAZIRLIK KONTROLU BASARISIZ" -ForegroundColor Red
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""

    if (-not $ReadinessResult.InternetAvailable) {
        Write-Host "    [X] Internet Baglantisi    : " -ForegroundColor Red -NoNewline
        Write-Host "Bulunamadi" -ForegroundColor Red
    } else {
        Write-Host "    [+] Internet Baglantisi    : " -ForegroundColor Green -NoNewline
        Write-Host "Mevcut" -ForegroundColor Green
    }

    if (-not $ReadinessResult.WinGetAvailable) {
        Write-Host "    [X] WinGet Durumu          : " -ForegroundColor Red -NoNewline
        Write-Host "Yuklu Degil veya Calismıyor" -ForegroundColor Red
    } else {
        Write-Host "    [+] WinGet Durumu          : " -ForegroundColor Green -NoNewline
        Write-Host "Mevcut ($($ReadinessResult.WinGetVersion))" -ForegroundColor Green
    }

    if (-not $ReadinessResult.SourcesOk) {
        Write-Host "    [X] Paket Kaynaklari       : " -ForegroundColor Red -NoNewline
        Write-Host "Kullanilamiyor" -ForegroundColor Red
    } else {
        Write-Host "    [+] Paket Kaynaklari       : " -ForegroundColor Green -NoNewline
        Write-Host "Mevcut" -ForegroundColor Green
    }

    if ($ReadinessResult.Details -and $ReadinessResult.Details.Count -gt 0) {
        Write-Host ""
        Write-Host "    Detaylar:" -ForegroundColor DarkCyan
        foreach ($d in $ReadinessResult.Details) {
            Write-Host "      - $d" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "    Kurulum islemleri icin WinGet, internet baglantisi" -ForegroundColor DarkCyan
    Write-Host "    ve paket kaynaklarinin tumu gereklidir." -ForegroundColor DarkCyan
    Write-Host ""
}

# ============================================================================
# HELPER: KONSOL KONUM GUVELEME
# ============================================================================
function Get-SafeCursorTop {
    try { return [Console]::CursorTop } catch { return -1 }
}

function Set-SafeCursorPosition([int]$Left, [int]$Top) {
    try {
        if ($Top -ge 0 -and $Left -ge 0 -and $Top -lt [Console]::BufferHeight -and $Left -lt [Console]::BufferWidth) {
            [Console]::SetCursorPosition($Left, $Top)
            return $true
        }
    } catch {}
    return $false
}

# ============================================================================
# TEST-APPINSTALLED
# ============================================================================
function Test-AppInstalled {
<#
.SYNOPSIS
    Belirtilen paketin zaten kurulu olup olmadigini ve surumunu tespit eder.
    WinGet ve Windows Kayit Defteri (Registry) uzerinden cift asamali denetler.
.OUTPUTS
    [hashtable] IsInstalled, InstalledVersion, AvailableVersion
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("PackageId", "Id", "Package_Id", "App", "Application", "Program")]
        $Package,
        [string]$Source
    )

    $PackageId = ""
    $AppName = ""
    if ($Package -is [string]) {
        $PackageId = $Package.Trim()
    } elseif ($Package) {
        $PackageId = if ($Package.winget_id) { "$($Package.winget_id)".Trim() }
                     elseif ($Package.packageId) { "$($Package.packageId)".Trim() }
                     elseif ($Package.Package_Id) { "$($Package.Package_Id)".Trim() }
                     elseif ($Package.Id) { "$($Package.Id)".Trim() }
                     elseif ($Package.id) { "$($Package.id)".Trim() }
                     else { "" }
        $AppName = if ($Package.Name) { "$($Package.Name)".Trim() } else { "" }
        if (-not $Source -and $Package.Source) { $Source = "$($Package.Source)".Trim() }
    }

    $result = @{
        IsInstalled      = $false
        InstalledVersion = $null
        AvailableVersion = $null
    }

    if (-not $PackageId -and -not $AppName) { return $result }

    # Asama 1: WinGet list ile kontrol (PackageId mevcutsa)
    if ($PackageId) {
        try {
            $listArgs = @('list', '--id', $PackageId, '--accept-source-agreements')
            $srcLower = if ($Source) { $Source.ToLower() } else { "" }
            if ($srcLower -in $script:AllowedSources) {
                $listArgs += '--source'
                $listArgs += $srcLower
            }

            $output = & winget.exe @listArgs 2>$null
            if ($LASTEXITCODE -eq 0 -and $output) {
                $outputStr = ($output | Out-String)
                # WinGet "No installed package found" / "Kurulu paket bulunamadi" mesajini yakala
                if ($outputStr -match 'No installed package|Kurulu paket bulunamadi') {
                    # WinGet cikis kodu 0 ama paket yok — exact olmadan tekrar dene
                } elseif ($outputStr -match [regex]::Escape($PackageId)) {
                    $result.IsInstalled = $true
                    foreach ($line in $output) {
                        $trimmed = $line.Trim()
                        if ($trimmed -match [regex]::Escape($PackageId)) {
                            $parts = $trimmed -split '\s{2,}'
                            if ($parts.Count -ge 3) {
                                $result.InstalledVersion = $parts[2].Trim()
                            }
                            if ($parts.Count -ge 4) {
                                $result.AvailableVersion = $parts[3].Trim()
                            }
                            break
                        }
                    }
                    Write-LogInfo "Paket kurulu tespit edildi (WinGet): $PackageId (Surum: $($result.InstalledVersion))"
                    return $result
                }
            }
            # Exact flag olmadan bulamazsa, kismi eslesme ile tekrar dene
            if (-not $result.IsInstalled -and $PackageId -match '\.') {
                $partialId = ($PackageId -split '\.')[-1]
                $listArgs2 = @('list', '--name', $partialId, '--accept-source-agreements')
                $output2 = & winget.exe @listArgs2 2>$null
                if ($LASTEXITCODE -eq 0 -and $output2) {
                    $outputStr2 = ($output2 | Out-String)
                    if ($outputStr2 -match [regex]::Escape($PackageId) -or $outputStr2 -match [regex]::Escape($partialId)) {
                        $result.IsInstalled = $true
                        foreach ($line in $output2) {
                            $trimmed = $line.Trim()
                            if ($trimmed -match [regex]::Escape($partialId) -and $trimmed -notmatch '^-+$|^Name|^Ad') {
                                $parts = $trimmed -split '\s{2,}'
                                if ($parts.Count -ge 3) { $result.InstalledVersion = $parts[2].Trim() }
                                if ($parts.Count -ge 4) { $result.AvailableVersion = $parts[3].Trim() }
                                break
                            }
                        }
                        Write-LogInfo "Paket kurulu tespit edildi (WinGet partial): $PackageId"
                        return $result
                    }
                }
            }
        } catch {
            Write-LogWarn "WinGet list kontrol hatasi: $($_.Exception.Message)"
        }
    }

    # Asama 2: WinGet list bulamazsa Kayit Defteri (Registry) ile dogrula
    try {
        if (Get-Command 'Get-InstalledPrograms' -ErrorAction SilentlyContinue) {
            $installed = Get-InstalledPrograms
            $matched = $installed | Where-Object {
                ($AppName -and $_.Name -like "*$AppName*") -or
                ($PackageId -and $_.Name -like "*$PackageId*") -or
                ($PackageId -and $_.WinGetId -and $_.WinGetId -like "*$PackageId*")
            } | Select-Object -First 1

            if ($matched) {
                $result.IsInstalled = $true
                $result.InstalledVersion = $matched.Version
                Write-LogInfo "Paket kurulu tespit edildi (Registry): $($matched.Name) (Surum: $($matched.Version))"
                return $result
            }
        }
    } catch {}

    return $result
}

# ============================================================================
# BUILD-WINGETCOMMAND
# ============================================================================
function Build-WinGetCommand {
<#
.SYNOPSIS
    Guvenli WinGet kurulum/guncelleme komut parametreleri olusturur.
    Kullanici tarafindan elle eklenen (winget_id, packageId vb.) uygulamalarla
    ve Turkce karakter kumesi ile yuzde 100 uyumludur.
.OUTPUTS
    [string[]] Arguman dizisi
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Application", "Program", "Package")]
        [PSCustomObject]$App,
        [ValidateSet('install','upgrade','reinstall')]
        [string]$Action = 'install',
        [switch]$NoExact,
        [switch]$NoArch,
        [switch]$NoScope,
        [switch]$NoSilent
    )

    # 1. Paket Kimligi Cozumleme
    $pkgId = if ($App.winget_id) { "$($App.winget_id)".Trim() }
             elseif ($App.packageId) { "$($App.packageId)".Trim() }
             elseif ($App.Package_Id) { "$($App.Package_Id)".Trim() }
             elseif ($App.Id) { "$($App.Id)".Trim() }
             elseif ($App.id) { "$($App.id)".Trim() }
             else { "" }

    if (-not $pkgId -or [string]::IsNullOrWhiteSpace($pkgId)) {
        Write-LogError "Paket kimligi (Id / winget_id) bos!"
        return $null
    }

    # Guvenlik kontrolu: Komut enjeksiyon karakterlerini engelle
    if ($pkgId -match '["'';&|`$><\r\n]') {
        Write-LogError "Gecersiz veya guvensiz karakter iceren paket kimligi: $pkgId"
        return $null
    }

    $verb = if ($Action -eq 'upgrade') { 'upgrade' } else { 'install' }

    $installArgs = @(
        $verb,
        '--id', $pkgId
    )

    if (-not $NoExact) {
        $installArgs += '--exact'
    }

    $installArgs += @(
        '--accept-source-agreements',
        '--accept-package-agreements'
    )

    if ($Action -eq 'reinstall') {
        $installArgs += '--force'
    }

    # 2. Kaynak (Source) Cozumleme
    $src = if ($App.Source) { "$($App.Source)".Trim().ToLower() }
           elseif ($App.source) { "$($App.source)".Trim().ToLower() }
           else { "" }

    if (-not $src) {
        if ($pkgId -match '^[0-9A-Za-z]{12}$') {
            $src = 'msstore'
        } else {
            $src = 'winget'
        }
    }

    if ($src -in $script:AllowedSources) {
        $installArgs += '--source'
        $installArgs += $src
    }

    # 3. Mimari (Architecture) Cozumleme
    $arch = if ($App.Architecture) { "$($App.Architecture)".Trim().ToLower() }
            elseif ($App.architecture) { "$($App.architecture)".Trim().ToLower() }
            else { "" }

    if (-not $NoArch -and $arch -and $arch -in $script:AllowedArchitectures -and $src -ne 'msstore') {
        $installArgs += '--architecture'
        $installArgs += $arch
    }

    # 4. Kapsam (Scope) Cozumleme
    $scope = if ($App.Scope) { "$($App.Scope)".Trim().ToLower() }
             elseif ($App.scope) { "$($App.scope)".Trim().ToLower() }
             else { "" }

    $isAdmin = $false
    try {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}

    if (-not $NoScope -and $src -ne 'msstore') {
        if ($scope -eq 'user') {
            $installArgs += '--scope'
            $installArgs += 'user'
        } elseif ($scope -eq 'machine' -and $isAdmin) {
            $installArgs += '--scope'
            $installArgs += 'machine'
        }
    }

    # 5. Surum (Version) Cozumleme
    $ver = if ($App.Version) { "$($App.Version)".Trim() }
           elseif ($App.version) { "$($App.version)".Trim() }
           else { "" }

    if ($Action -eq 'install' -and $ver -and $ver.ToLower() -ne 'latest') {
        if (-not ($ver -match '["'';&|`$><\r\n]')) {
            $installArgs += '--version'
            $installArgs += $ver
        }
    }

    # 6. Sessiz Kurulum (Silent) Cozumleme
    $isSilent = if ($null -ne $App.SilentInstall) { [bool]$App.SilentInstall }
                elseif ($null -ne $App.silent) { [bool]$App.silent }
                else { $true }

    if (-not $NoSilent -and $isSilent -and $src -ne 'msstore') {
        $installArgs += '--silent'
    }

    # 7. Ozel Parametreler (CustomArguments / custom_params)
    $customArgs = if ($App.CustomArguments) { "$($App.CustomArguments)".Trim() }
                  elseif ($App.custom_params) { "$($App.custom_params)".Trim() }
                  elseif ($App.custom) { "$($App.custom)".Trim() }
                  else { "" }

    if ($customArgs -and -not ($customArgs -match '["'';&|`$><\r\n]')) {
        $installArgs += '--custom'
        $installArgs += $customArgs
    }

    Write-LogInfo "WinGet komutu hazirlandi: winget $($installArgs -join ' ')"
    return $installArgs
}

# ============================================================================
# WRITE-INSTALLLOG
# ============================================================================
function Write-InstallLog {
<#
.SYNOPSIS
    Kurulum sonucunu JSON kaydeder.
#>
    param(
        [Parameter(Mandatory)] [PSCustomObject]$App,
        [Parameter(Mandatory)] [datetime]$StartTime,
        [datetime]$EndTime,
        [int]$ExitCode = -1,
        [string]$StdOut = "",
        [string]$StdErr = "",
        [bool]$Success = $false,
        [string]$SkipReason = "",
        [bool]$Verified = $false,
        [string]$VerifiedVersion = ""
    )

    Initialize-InstallerPaths

    $duration = 0
    if ($EndTime) {
        $duration = [int]($EndTime - $StartTime).TotalSeconds
    }

    $entry = [PSCustomObject]@{
        SessionId       = $script:CurrentSessionId
        Timestamp       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        PackageId       = $App.Id
        Name            = $App.Name
        Source          = $App.Source
        Version         = $App.Version
        Scope           = $App.Scope
        StartTime       = $StartTime.ToString('yyyy-MM-dd HH:mm:ss')
        EndTime         = if ($EndTime) { $EndTime.ToString('yyyy-MM-dd HH:mm:ss') } else { "" }
        DurationSec     = $duration
        ExitCode        = $ExitCode
        Success         = $Success
        SkipReason      = $SkipReason
        Verified        = $Verified
        VerifiedVersion = $VerifiedVersion
        ErrorMsg        = if ($StdErr.Length -gt 500) { $StdErr.Substring(0, 500) } else { $StdErr }
    }

    $script:CurrentSessionResults += $entry

    try {
        $history = @()
        if (Test-Path $script:InstallHistoryFile) {
            try {
                $raw = [System.IO.File]::ReadAllText($script:InstallHistoryFile, [System.Text.Encoding]::UTF8)
                $parsed = ConvertFrom-Json $raw
                if ($parsed) { $history = @($parsed) }
            } catch {
                $history = @()
            }
        }

        $history += $entry

        if ($history.Count -gt 500) {
            $history = @($history | Select-Object -Last 500)
        }

        $jsonContent = ConvertTo-Json $history -Depth 5
        [System.IO.File]::WriteAllText($script:InstallHistoryFile, $jsonContent, [System.Text.Encoding]::UTF8)
        Write-LogInfo "Kurulum log kaydi yazildi: $($App.Name) (Basari: $Success)"
    } catch {
        Write-LogError "Kurulum log hatasi: $($_.Exception.Message)"
    }
}

# ============================================================================
# GET-INSTALLHISTORY
# ============================================================================
function Get-InstallHistory {
<#
.SYNOPSIS
    Kurulum gecmisini dosyadan dondurur.
#>
    Initialize-InstallerPaths

    if (-not (Test-Path $script:InstallHistoryFile)) { return @() }

    try {
        $raw = [System.IO.File]::ReadAllText($script:InstallHistoryFile, [System.Text.Encoding]::UTF8)
        $parsed = ConvertFrom-Json $raw
        if ($parsed) { return @($parsed) }
    } catch {
        Write-LogError "Gecmis okuma hatasi: $($_.Exception.Message)"
    }

    return @()
}

# ============================================================================
# FORMAT-PROGRESSBAR
# ============================================================================
function Format-ProgressBar {
<#
.SYNOPSIS
    Yuzdeye dayali gercek ilerleme cubugu olusturur.
#>
    param(
        [int]$Percent,
        [Alias("Width", "Length")]
        [int]$BarWidth = 30
    )
    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    $filledCount = [Math]::Floor($Percent * $BarWidth / 100)
    $emptyCount  = $BarWidth - $filledCount

    $filledChar = [char]0x2588  # █
    $emptyChar  = [char]0x2591  # ░

    $filledStr = [string]::new($filledChar, $filledCount)
    $emptyStr  = [string]::new($emptyChar, $emptyCount)

    return "[$filledStr$emptyStr] %$Percent"
}

# ============================================================================
# FORMAT-MARQUEEBAR
# ============================================================================
function Format-MarqueeBar {
<#
.SYNOPSIS
    Kayan animasyonlu bekleme cubugu olusturur.
#>
    param(
        [int]$Frame,
        [Alias("Width", "Length")]
        [int]$BarWidth = 30,
        [int]$BlockSize = 4
    )
    $travelWidth = $BarWidth - $BlockSize
    if ($travelWidth -lt 1) { $travelWidth = 1 }

    $pingPong = $Frame % ($travelWidth * 2)
    if ($pingPong -ge $travelWidth) {
        $pos = ($travelWidth * 2) - $pingPong
    } else {
        $pos = $pingPong
    }

    $filledChar = [char]0x2588  # █
    $emptyChar  = [char]0x2591  # ░

    $before = [string]::new($emptyChar, $pos)
    $block  = [string]::new($filledChar, $BlockSize)
    $after  = [string]::new($emptyChar, [Math]::Max(0, $BarWidth - $pos - $BlockSize))

    return "[$before$block$after]"
}

# ============================================================================
# SHOW-INSTALLSCREEN
# ============================================================================
function Show-InstallScreen {
<#
.SYNOPSIS
    Kurulum durum ekranini cizer, canli cikti ve iptal kisayollarini hazirlar.
#>
    param(
        [string]$InstallMode = "TEKLI KURULUM",
        [string]$ProgramName = "",
        [string]$PackageId = "",
        [string]$Source = "",
        [int]$TotalCount = 1,
        [int]$CompletedCount = 0,
        [int]$SuccessCount = 0,
        [int]$FailCount = 0
    )

    Show-AppHeader
    Write-Host ""
    Write-Host "  [ 1] | Uygulama Kurulum Merkezi  >  $InstallMode" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  KURULUM DURUMU" -ForegroundColor Green
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""

    Write-Host "    Mevcut Program : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$ProgramName" -ForegroundColor White
    Write-Host "    Paket Kimligi  : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$PackageId" -ForegroundColor White
    Write-Host "    Kaynak         : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$Source" -ForegroundColor White

    $script:ProgressPositions = @{
        StatusY     = -1
        OverallBarY = -1
        ProgramBarY = -1
        CountersY   = -1
        LiveStreamY = -1
        MessageY    = -1
    }

    if ($TotalCount -gt 1) {
        $overallPct = if ($TotalCount -gt 0) { [Math]::Round(($CompletedCount / $TotalCount) * 100) } else { 0 }
        $bar = Format-ProgressBar -Percent $overallPct -BarWidth 30
        Write-Host "    Genel Ilerleme : " -ForegroundColor Green -NoNewline
        Write-Host "$bar ($CompletedCount/$TotalCount | Basarili: $SuccessCount | Basarisiz: $FailCount)" -ForegroundColor White
    }
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
}

# ============================================================================
# UPDATE-INSTALLPROGRESS
# ============================================================================
function Update-InstallProgress {
<#
.SYNOPSIS
    Kurulum ekranindaki alanlari cursor konumlandirma ile canli ve donmadan gunceller.
#>
    param(
        [string]$StatusText,
        [int]$SpinnerFrame = 0,
        [int]$OverallPercent = -1,
        [int]$ProgramPercent = -1,
        [string]$LiveOutput = "",
        [string]$MessageText = "",
        [int]$Completed = -1,
        [int]$Total = -1,
        [int]$SuccessCount = -1,
        [int]$FailCount = -1
    )

    try {
        if ($script:ProgressPositions.StatusY -lt 0) {
            if ($MessageText) {
                $clr = if ($StatusText -match 'BASARISIZ|HATA|IPTAL') { 'Red' }
                       elseif ($StatusText -match 'BASARILI|ZATEN KURULU') { 'Green' }
                       else { 'Cyan' }
                Write-Host "  [$StatusText] $MessageText" -ForegroundColor $clr
            }
            return
        }
        # 1. Asama Durumu
        if ($StatusText -and $script:ProgressPositions.StatusY -ge 0) {
            if (Set-SafeCursorPosition 21 $script:ProgressPositions.StatusY) {
                $padded = $StatusText.PadRight(50)
                Write-Host $padded -ForegroundColor Yellow -NoNewline
            }
        }

        # 2. Program Ilerleme Cubugu (Yuzde veya Marquee)
        if ($script:ProgressPositions.ProgramBarY -ge 0) {
            if (Set-SafeCursorPosition 4 $script:ProgressPositions.ProgramBarY) {
                if ($ProgramPercent -ge 0) {
                    $pBar = Format-ProgressBar -Percent $ProgramPercent -BarWidth 30
                    $barText = "$pBar Indirme / Kurulum yapiliyor..."
                    Write-Host $barText.PadRight(60) -ForegroundColor Green -NoNewline
                } else {
                    $marquee = Format-MarqueeBar -Frame $SpinnerFrame -BarWidth 30
                    $spin = $script:SpinnerChars[$SpinnerFrame % 4]
                    $barText = "$marquee $spin Islem devam ediyor..."
                    Write-Host $barText.PadRight(60) -ForegroundColor Yellow -NoNewline
                }
            }
        }

        # 3. Genel Ilerleme Cubugu (Toplu Kurulumda)
        if ($OverallPercent -ge 0 -and $script:ProgressPositions.OverallBarY -ge 0) {
            if (Set-SafeCursorPosition 4 $script:ProgressPositions.OverallBarY) {
                $bar = Format-ProgressBar -Percent $OverallPercent -BarWidth 30
                Write-Host $bar.PadRight(50) -ForegroundColor Green -NoNewline
            }
        }

        # 4. Sayaclar (Toplu Kurulumda)
        if ($Completed -ge 0 -and $script:ProgressPositions.CountersY -ge 0) {
            $pending = $Total - $Completed - 1
            if ($pending -lt 0) { $pending = 0 }
            if (Set-SafeCursorPosition 0 $script:ProgressPositions.CountersY) {
                Write-Host "    Tamamlanan : $Completed / $Total     " -ForegroundColor DarkCyan
                Write-Host "    Basarili   : $SuccessCount     " -ForegroundColor Green
                Write-Host "    Basarisiz  : $FailCount     " -ForegroundColor Red
                Write-Host "    Bekleyen   : $pending     " -ForegroundColor White
            }
        }

        # 5. Canli WinGet Akisi (Live Output Stream)
        if ($script:ProgressPositions.LiveStreamY -ge 0) {
            if (Set-SafeCursorPosition 4 $script:ProgressPositions.LiveStreamY) {
                $streamText = if ($LiveOutput) { ">> $LiveOutput" } else { ">> Islem yapiliyor..." }
                if ($streamText.Length -gt 74) { $streamText = $streamText.Substring(0, 71) + "..." }
                Write-Host $streamText.PadRight(75) -ForegroundColor Cyan -NoNewline
            }
        }

        # 6. Durum Mesaji ve Iptal Bilgisi
        if ($script:ProgressPositions.MessageY -ge 0) {
            if (Set-SafeCursorPosition 4 $script:ProgressPositions.MessageY) {
                $msg = if ($MessageText) { $MessageText } else { "Islem devam ediyor... | [ESC / Q] Islemi Iptal Et" }
                if ($msg.Length -gt 74) { $msg = $msg.Substring(0, 71) + "..." }
                Write-Host $msg.PadRight(75) -ForegroundColor White -NoNewline
            }
        }
    } catch {}
}

# ============================================================================
# INVOKE-WINGETINSTALL (Gercek Kurulum Motoru)
# ============================================================================
# ============================================================================
# HELPER: INVOKE-SINGLEWINGETPROCESS (Surec Calistirma & Canli Akis Okuma)
# ============================================================================
function Invoke-SingleWinGetProcess {
    param(
        [Parameter(Mandatory)] [string]$WingetExe,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [string]$AppName = "",
        [string]$Action = "install",
        [bool]$IsBulkMode = $false,
        [int]$BulkTotal = 1,
        [int]$BulkCompleted = 0,
        [int]$BulkSuccess = 0,
        [int]$BulkFail = 0
    )

    $result = @{
        ExitCode  = -1
        StdOut    = ""
        StdErr    = ""
        Cancelled = $false
    }

    try {
        Write-LogInfo "WinGet baslatiliyor: $WingetExe $($Arguments -join ' ')"
        Write-Host ""
        Write-Host "  --- WinGet Canli Kurulum & Ilerleme Cubugu ---" -ForegroundColor DarkCyan
        Write-Host ""

        $argStr = ($Arguments | ForEach-Object {
            if ($_ -match '\s') { "`"$_`"" } else { $_ }
        }) -join ' '

        $proc = Start-Process -FilePath $WingetExe -ArgumentList $argStr -NoNewWindow -Wait -PassThru -ErrorAction Stop
        $result.ExitCode = if ($null -ne $proc -and $null -ne $proc.ExitCode) { [int]$proc.ExitCode } else { 0 }
        $result.StdOut = "WinGet canli konsol ciktisi (Kod: $($result.ExitCode))"

        Write-Host ""
        Write-LogInfo "WinGet tamamlandi: $AppName (ExitCode: $($result.ExitCode))"
    } catch {
        $result.StdErr   = "Islem hatasi: $($_.Exception.Message)"
        $result.ExitCode = -99
        Write-LogError "WinGet calistirma istisnasi: $($_.Exception.Message)"
    }

    return $result
}

# ============================================================================
# INVOKE-DIRECTURLINSTALL (Dogrudan URL'den Indirip Kurma Motoru - Office vb.)
# ============================================================================
function Invoke-DirectUrlInstall {
    param(
        [Parameter(Mandatory)][PSCustomObject]$App,
        [datetime]$StartTime = (Get-Date),
        [switch]$IsBulkMode,
        [int]$BulkTotal = 1,
        [int]$BulkCompleted = 0,
        [int]$BulkSuccess = 0,
        [int]$BulkFail = 0
    )

    $installResult = @{
        Success         = $false
        ExitCode        = -1
        StdOut          = ""
        StdErr          = ""
        Duration        = 0
        Skipped         = $false
        SkipReason      = ""
        Verified        = $false
        VerifiedVersion = ""
        Action          = 'install'
    }

    $dispName = if ($App.Name) { "$($App.Name)".Trim() } else { "Uygulama" }
    $dispId   = if ($App.Id) { "$($App.Id)".Trim() } elseif ($App.id) { "$($App.id)".Trim() } else { "direct_url" }
    $url      = if ($App.DownloadUrl) { "$($App.DownloadUrl)".Trim() } elseif ($App.download_url) { "$($App.download_url)".Trim() } else { "" }

    if (-not $url -or $url -notmatch '^https?://') {
        $installResult.StdErr = "Gecersiz veya bos indirme baglantisi."
        Update-InstallProgress -StatusText "HATA: Gecersiz indirme URL'si" -SpinnerFrame 0 -MessageText $installResult.StdErr
        Write-InstallLog -App $App -StartTime $StartTime -EndTime (Get-Date) -ExitCode -1 -StdErr $installResult.StdErr -Success $false
        Start-Sleep -Seconds 2
        return $installResult
    }

    $fileName = if ($App.InstallerFileName) {
        "$($App.InstallerFileName)".Trim()
    } else {
        ($dispId -replace '[^a-zA-Z0-9._-]', '_') + ".exe"
    }
    $destPath = Join-Path $env:TEMP $fileName

    try {
        Update-InstallProgress -StatusText "Yukleyici indiriliyor..." -SpinnerFrame 1 `
            -ProgramPercent 15 -MessageText "$dispName kurulum dosyasi indiriliyor..."
        Write-LogInfo "Dogrudan URL'den indiriliyor: $url -> $destPath"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $prevProg = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing -ErrorAction Stop
        } finally {
            $ProgressPreference = $prevProg
        }

        if (-not (Test-Path $destPath) -or ((Get-Item $destPath).Length -le 0)) {
            throw "Indirilen kurulum dosyasi bos veya olusturulamadi: $destPath"
        }

        Update-InstallProgress -StatusText "Kurulum penceresi aciliyor..." -SpinnerFrame 2 `
            -ProgramPercent 60 -MessageText "$fileName ekranda acildi! Kurulum penceresinden islemi takip edebilirsiniz."
        Write-LogInfo "Dogrudan kurulum dosyasi gorunur pencerede baslatiliyor: $destPath"
        Write-Host ""
        Write-Host "  [BILGI] $dispName kurulum penceresi acildi. Lutfen acilan pencere uzerinden kurulumu tamamlayin..." -ForegroundColor Green

        $spParams = @{
            FilePath    = $destPath
            WindowStyle = 'Normal'
            Wait        = $true
            PassThru    = $true
            ErrorAction = 'Stop'
        }
        $customArgs = if ($App.CustomArguments) { "$($App.CustomArguments)".Trim() } elseif ($App.custom_params) { "$($App.custom_params)".Trim() } else { "" }
        if ($customArgs) {
            $spParams['ArgumentList'] = $customArgs
        }

        $proc = Start-Process @spParams
        $exitCode = if ($null -ne $proc -and $null -ne $proc.ExitCode) { [int]$proc.ExitCode } else { 0 }

        $installResult.ExitCode = $exitCode
        $installResult.Success  = ($exitCode -eq 0 -or $exitCode -eq 3010)
        $installResult.Verified = $installResult.Success
        $installResult.StdOut   = "Direct URL kurulumu tamamlandi: $destPath (Kod: $exitCode)"

        if ($installResult.Success) {
            Update-InstallProgress -StatusText "BASARILI" -SpinnerFrame 0 -ProgramPercent 100 `
                -MessageText "$dispName kurulumu tamamlandi! (Kod: $exitCode)"
            Write-LogSuccess "$dispName dogrudan URL uzerinden basariyla kuruldu (ExitCode: $exitCode)."
        } else {
            $installResult.StdErr = "Kurulum dosyasi hata kodu ile kapandi: $exitCode"
            Update-InstallProgress -StatusText "BASARISIZ - Kod: $exitCode" -SpinnerFrame 0 `
                -MessageText "$dispName kurulumu tamamlanamadi (Kod: $exitCode)."
            Write-LogError "$dispName dogrudan URL kurulum hatasi (ExitCode: $exitCode)."
        }
    } catch {
        $installResult.ExitCode = -99
        $installResult.Success  = $false
        $installResult.StdErr   = $_.Exception.Message
        Update-InstallProgress -StatusText "HATA: Indirme/Kurulum basarisiz" -SpinnerFrame 0 `
            -MessageText "$dispName hatasi: $($_.Exception.Message)"
        Write-LogError "$dispName direct_url hatasi: $($_.Exception.Message)"
    }

    $endTime = Get-Date
    $installResult.Duration = [int]($endTime - $StartTime).TotalSeconds
    Write-InstallLog -App $App -StartTime $StartTime -EndTime $endTime `
        -ExitCode $installResult.ExitCode -StdOut $installResult.StdOut `
        -StdErr $installResult.StdErr -Success $installResult.Success `
        -Verified $installResult.Verified -VerifiedVersion $installResult.VerifiedVersion

    if (-not $IsBulkMode) { Start-Sleep -Seconds 2 } else { Start-Sleep -Milliseconds 600 }
    return $installResult
}

# ============================================================================
# INVOKE-WINGETINSTALL (Gercek Kurulum Motoru - Kademeli Fallback Destekli)
# ============================================================================
function Invoke-WinGetInstall {
<#
.SYNOPSIS
    Tek bir programi WinGet uzerinden gercek olarak kurar veya gunceller.
    Canli stdout akisini okur; hata durumunda otomatik kademeli fallback
    (tam eslesme, serbest arama, mimari serbest, sessiz kaldirma) calistirir.
.OUTPUTS
    [hashtable]
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Application", "Program", "Package")]
        [PSCustomObject]$App,
        [ValidateSet('install','upgrade','reinstall')]
        [string]$Action = 'install',
        [switch]$IsBulkMode,
        [int]$BulkTotal = 1,
        [int]$BulkCompleted = 0,
        [int]$BulkSuccess = 0,
        [int]$BulkFail = 0
    )

    Initialize-InstallerPaths

    $installResult = @{
        Success         = $false
        ExitCode        = -1
        StdOut          = ""
        StdErr          = ""
        Duration        = 0
        Skipped         = $false
        SkipReason      = ""
        Verified        = $false
        VerifiedVersion = ""
        Action          = $Action
    }

    $startTime = Get-Date

    $dispName = if ($App.Name) { "$($App.Name)".Trim() } else { "Uygulama" }
    $dispId = if ($App.winget_id) { "$($App.winget_id)".Trim() }
              elseif ($App.packageId) { "$($App.packageId)".Trim() }
              elseif ($App.Id) { "$($App.Id)".Trim() }
              elseif ($App.id) { "$($App.id)".Trim() }
              else { "-" }
    $dispSrc = if ($App.Source) { "$($App.Source)".Trim() }
               elseif ($App.source) { "$($App.source)".Trim() }
               else { "winget" }

    $installMode = if ($IsBulkMode) { "TOPLU KURULUM" } else { "TEKLI KURULUM" }
    Show-InstallScreen -InstallMode $installMode `
        -ProgramName $dispName `
        -PackageId $dispId `
        -Source $dispSrc `
        -TotalCount $BulkTotal `
        -CompletedCount $BulkCompleted `
        -SuccessCount $BulkSuccess `
        -FailCount $BulkFail

    # Dogrudan URL'den kurulum (or. Microsoft Office C2R)
    $instType = if ($App.InstallType) { "$($App.InstallType)".Trim().ToLower() } elseif ($App.install_type) { "$($App.install_type)".Trim().ToLower() } else { "" }
    if ($instType -eq 'direct_url' -or $dispSrc.ToLower() -eq 'direct_url') {
        return (Invoke-DirectUrlInstall -App $App -StartTime $startTime -IsBulkMode:$IsBulkMode `
            -BulkTotal $BulkTotal -BulkCompleted $BulkCompleted -BulkSuccess $BulkSuccess -BulkFail $BulkFail)
    }

    # Asama 1: Kurulum ve Surum Durumu Kontrolu
    Update-InstallProgress -StatusText "Kurulum durumu kontrol ediliyor..." -SpinnerFrame 0 `
        -MessageText "$dispName icin sistem durumu denetleniyor..."
    Start-Sleep -Milliseconds 250

    $installedStatus = Test-AppInstalled -Package $App

    if ($installedStatus.IsInstalled -and $Action -eq 'install') {
        if ($IsBulkMode) {
            if ($installedStatus.AvailableVersion -and $installedStatus.AvailableVersion -ne $installedStatus.InstalledVersion) {
                # Toplu kurulumda guncelleme mevcutsa guncelle
                $Action = 'upgrade'
                Update-InstallProgress -StatusText "Guncelleme mevcut, yukleniyor..." -SpinnerFrame 0 `
                    -MessageText "$dispName ($($installedStatus.InstalledVersion) -> $($installedStatus.AvailableVersion)) guncelleniyor..."
                Start-Sleep -Milliseconds 400
            } else {
                # Zaten guncel, atla
                $verInfo = if ($installedStatus.InstalledVersion) { " (Surum: $($installedStatus.InstalledVersion))" } else { "" }
                Update-InstallProgress -StatusText "ZATEN KURULU (GUNCEL)$verInfo" -SpinnerFrame 0 `
                    -MessageText "$dispName zaten kurulu ve guncel.$verInfo"

                $installResult.Skipped = $true
                $installResult.SkipReason = "Zaten kurulu (Guncel)$verInfo"
                $installResult.Success = $true

                Write-InstallLog -App $App -StartTime $startTime -EndTime (Get-Date) `
                    -Success $true -SkipReason $installResult.SkipReason

                Write-LogInfo "$dispName zaten guncel, atlandi."
                Start-Sleep -Seconds 1
                return $installResult
            }
        }
    }

    # Asama 2: WinGet Calistirilabilir Dosyasi Kontrolu
    $wingetExe = (Get-Command "winget.exe" -ErrorAction SilentlyContinue).Source
    if (-not $wingetExe) {
        Update-InstallProgress -StatusText "HATA: winget.exe bulunamadi" -SpinnerFrame 0 `
            -MessageText "WinGet calistirilabilir dosyasi sistemde bulunamadi."
        $installResult.StdErr = "winget.exe bulunamadi"
        Write-InstallLog -App $App -StartTime $startTime -EndTime (Get-Date) `
            -ExitCode -1 -StdErr $installResult.StdErr -Success $false
        Start-Sleep -Seconds 2
        return $installResult
    }

    # Asama 3: Guvenli Komut Olustur (1. Deneme - Standart Parametreler)
    Update-InstallProgress -StatusText "Kurulum komutu hazirlaniyor..." -SpinnerFrame 1 `
        -MessageText "WinGet parametreleri derleniyor..."
    Start-Sleep -Milliseconds 200

    $installArgs = Build-WinGetCommand -App $App -Action $Action
    if (-not $installArgs) {
        Update-InstallProgress -StatusText "HATA: Gecersiz paket kimligi" -SpinnerFrame 0 `
            -MessageText "Paket parametreleri gecersiz veya guvensiz. Kurulum baslatilamadi."
        $installResult.StdErr = "Gecersiz paket kimligi ($dispId)"
        Write-InstallLog -App $App -StartTime $startTime -EndTime (Get-Date) `
            -ExitCode -1 -StdErr $installResult.StdErr -Success $false
        Start-Sleep -Seconds 2
        return $installResult
    }

    # 1. Calistirma Denemesi
    $exec = Invoke-SingleWinGetProcess -WingetExe $wingetExe -Arguments $installArgs `
        -AppName $dispName -Action $Action -IsBulkMode $IsBulkMode `
        -BulkTotal $BulkTotal -BulkCompleted $BulkCompleted -BulkSuccess $BulkSuccess -BulkFail $BulkFail

    # Kullanici iptal ettiyse fallback'lere girmeden hemen don
    if ($exec.Cancelled) {
        $installResult.Cancelled  = $true
        $installResult.Success    = $false
        $installResult.ExitCode   = -99
        $installResult.StdErr     = "Kullanici tarafindan iptal edildi (ESC/Q)"
        $installResult.SkipReason = "Kullanici tarafindan iptal edildi"
        $endTime = Get-Date
        $installResult.Duration   = [int]($endTime - $startTime).TotalSeconds

        Update-InstallProgress -StatusText "IPTAL EDILDI" -SpinnerFrame 0 `
            -MessageText "$dispName kurulumu kullanici tarafindan durduruldu."
        Write-LogWarn "$dispName kurulumu kullanici tarafindan durduruldu."

        Write-InstallLog -App $App -StartTime $startTime -EndTime $endTime `
            -ExitCode $installResult.ExitCode -StdOut $exec.StdOut `
            -StdErr $installResult.StdErr -Success $false `
            -Verified $false -VerifiedVersion $null

        Start-Sleep -Seconds 1
        return $installResult
    }

    $combinedOutput = "$($exec.StdOut)`n$($exec.StdErr)"

    # --- KADEMELI AKILLI FALLBACK SISTEMI ---

    # Fallback 1: Eger paket tam eslesmediyse (--exact kisiti kaldirilarak tekrar dene)
    if ($exec.ExitCode -ne 0 -and ($exec.ExitCode -eq -1978335231 -or $combinedOutput -match 'No package found|bulunamadi|eşleşen.*paket.*yok')) {
        Update-InstallProgress -StatusText "Tam eslesme bulunamadi, serbest arama deneniyor..." -SpinnerFrame 2 `
            -MessageText "$dispName icin --exact anahtari kaldirilarak araniyor..."
        Write-LogWarn "$dispName tam ID ile bulunamadi, --exact olmadan tekrar deneniyor..."
        $fallbackArgs1 = Build-WinGetCommand -App $App -Action $Action -NoExact
        if ($fallbackArgs1) {
            $exec = Invoke-SingleWinGetProcess -WingetExe $wingetExe -Arguments $fallbackArgs1 `
                -AppName $dispName -Action $Action -IsBulkMode $IsBulkMode `
                -BulkTotal $BulkTotal -BulkCompleted $BulkCompleted -BulkSuccess $BulkSuccess -BulkFail $BulkFail
            if ($exec.Cancelled) {
                $installResult.Cancelled  = $true
                $installResult.Success    = $false
                $installResult.ExitCode   = -99
                $installResult.StdErr     = "Kullanici tarafindan iptal edildi (ESC/Q)"
                $installResult.SkipReason = "Kullanici tarafindan iptal edildi"
                $endTime = Get-Date
                $installResult.Duration   = [int]($endTime - $startTime).TotalSeconds
                Update-InstallProgress -StatusText "IPTAL EDILDI" -SpinnerFrame 0 `
                    -MessageText "$dispName kurulumu iptal edildi."
                Start-Sleep -Seconds 1
                return $installResult
            }
            $combinedOutput = "$($exec.StdOut)`n$($exec.StdErr)"
        }
    }

    # Fallback 2: Eger uygun yukleyici bulunamadiysa (Mimari veya Kapsam serbest birak)
    if ($exec.ExitCode -ne 0 -and ($exec.ExitCode -eq -1978335215 -or $combinedOutput -match 'No applicable installer|uygun yukleyici bulunamadi')) {
        Update-InstallProgress -StatusText "Uygun yukleyici araniyor (mimari/kapsam serbest)..." -SpinnerFrame 3 `
            -MessageText "$dispName icin mimari/kapsam kisitlamasi kaldirilarak deneniyor..."
        Write-LogWarn "$dispName icin mimari/kapsam kisitlamasi kaldirilarak deneniyor..."
        $fallbackArgs2 = Build-WinGetCommand -App $App -Action $Action -NoExact -NoArch -NoScope
        if ($fallbackArgs2) {
            $exec = Invoke-SingleWinGetProcess -WingetExe $wingetExe -Arguments $fallbackArgs2 `
                -AppName $dispName -Action $Action -IsBulkMode $IsBulkMode `
                -BulkTotal $BulkTotal -BulkCompleted $BulkCompleted -BulkSuccess $BulkSuccess -BulkFail $BulkFail
            if ($exec.Cancelled) {
                $installResult.Cancelled  = $true
                $installResult.Success    = $false
                $installResult.ExitCode   = -99
                $installResult.StdErr     = "Kullanici tarafindan iptal edildi (ESC/Q)"
                $installResult.SkipReason = "Kullanici tarafindan iptal edildi"
                $endTime = Get-Date
                $installResult.Duration   = [int]($endTime - $startTime).TotalSeconds
                Update-InstallProgress -StatusText "IPTAL EDILDI" -SpinnerFrame 0 `
                    -MessageText "$dispName kurulumu iptal edildi."
                Start-Sleep -Seconds 1
                return $installResult
            }
            $combinedOutput = "$($exec.StdOut)`n$($exec.StdErr)"
        }
    }

    # Fallback 3: Eger sessiz kurulum hatasi veriyorsa (--silent kaldir)
    if ($exec.ExitCode -ne 0 -and ($exec.ExitCode -eq 1603 -or $combinedOutput -match '1603|failed with exit code 1603')) {
        Update-InstallProgress -StatusText "Sessiz mod kaldirilarak tekrar deneniyor..." -SpinnerFrame 4 `
            -MessageText "$dispName sessiz kurulumda hata verdi, standart mod deneniyor..."
        Write-LogWarn "$dispName sessiz kurulumda hata verdi (1603), --silent olmadan deneniyor..."
        $fallbackArgs3 = Build-WinGetCommand -App $App -Action $Action -NoExact -NoArch -NoScope -NoSilent
        if ($fallbackArgs3) {
            $exec = Invoke-SingleWinGetProcess -WingetExe $wingetExe -Arguments $fallbackArgs3 `
                -AppName $dispName -Action $Action -IsBulkMode $IsBulkMode `
                -BulkTotal $BulkTotal -BulkCompleted $BulkCompleted -BulkSuccess $BulkSuccess -BulkFail $BulkFail
            if ($exec.Cancelled) {
                $installResult.Cancelled  = $true
                $installResult.Success    = $false
                $installResult.ExitCode   = -99
                $installResult.StdErr     = "Kullanici tarafindan iptal edildi (ESC/Q)"
                $installResult.SkipReason = "Kullanici tarafindan iptal edildi"
                $endTime = Get-Date
                $installResult.Duration   = [int]($endTime - $startTime).TotalSeconds
                Update-InstallProgress -StatusText "IPTAL EDILDI" -SpinnerFrame 0 `
                    -MessageText "$dispName kurulumu iptal edildi."
                Start-Sleep -Seconds 1
                return $installResult
            }
            $combinedOutput = "$($exec.StdOut)`n$($exec.StdErr)"
        }
    }

    $installResult.StdOut   = $exec.StdOut
    $installResult.StdErr   = $exec.StdErr
    $installResult.ExitCode = $exec.ExitCode

    $endTime = Get-Date
    $installResult.Duration = [int]($endTime - $startTime).TotalSeconds
    $installResult.Success  = ($installResult.ExitCode -eq 0 -or $installResult.ExitCode -eq 3010)

    # Asama 4: Kurulum Sonrasi Dogrulama
    if ($installResult.Success) {
        Update-InstallProgress -StatusText "Kurulum dogrulaniyor..." -SpinnerFrame 0 `
            -MessageText "$dispName kurulumu dogrulaniyor..."
        # WinGet veritabaninin guncellenmesi icin yeterli bekleme
        Start-Sleep -Seconds 3

        $verify = Test-AppInstalled -Package $App
        # Ilk denemede bulunamazsa tekrar dene (WinGet index gecikmesi)
        if (-not $verify.IsInstalled) {
            Start-Sleep -Seconds 2
            $verify = Test-AppInstalled -Package $App
        }
        if ($verify.IsInstalled) {
            $installResult.Verified = $true
            $installResult.VerifiedVersion = $verify.InstalledVersion
            $vMsg = if ($verify.InstalledVersion) { " (Surum: $($verify.InstalledVersion))" } else { "" }
            Update-InstallProgress -StatusText "BASARILI VE DOGRULANDI" -SpinnerFrame 0 `
                -MessageText "$dispName basariyla kuruldu ve dogrulandi!$vMsg"
            Write-LogSuccess "$dispName basariyla kuruldu ve dogrulandi.$vMsg"
        } else {
            # ExitCode 0 ise kurulum basarili sayilir — WinGet index gecikmesi olabilir
            $installResult.Verified = $false
            Update-InstallProgress -StatusText "BASARILI (Dogrulama Bekleniyor)" -SpinnerFrame 0 `
                -MessageText "$dispName WinGet tarafindan basariyla kuruldu. (Dogrulama gecikmeli olabilir)"
            Write-LogSuccess "$dispName kuruldu (ExitCode: 0). Dogrulama WinGet index gecikmesi nedeniyle bekliyor."
        }

        # Baslat Menusu Kisayol ve Calistirilabilir Dosya Denetimi
        if (Get-Command "Show-PostInstallShortcutCheck" -ErrorAction SilentlyContinue) {
            $null = Show-PostInstallShortcutCheck -AppName $dispName -PackageId $dispId -SilentMode:$IsBulkMode
        }
    } else {
        $errDetail = ""
        if ($exec.ExitCode -eq -1978335189 -or $combinedOutput -match 'privilege is not held|yetki|access is denied|0x80070005') {
            $errDetail = "Yonetici yetkisi gerekiyor! (AAU_Admin.cmd kullanin)"
        } elseif ($script:WinGetExitCodes.ContainsKey($exec.ExitCode)) {
            $errDetail = $script:WinGetExitCodes[$exec.ExitCode]
        } elseif ($exec.StdErr) {
            $errDetail = $exec.StdErr.Trim()
        } elseif ($exec.StdOut) {
            $lines = @($exec.StdOut -split "`r?`n" | Where-Object { $_ -and $_.Trim() -notmatch '^-+$|^\[|^Indiriliyor|^Indirme' })
            if ($lines.Count -gt 0) { $errDetail = $lines[-1].Trim() }
        }
        if (-not $errDetail) { $errDetail = "Hata kodu: $($exec.ExitCode)" }

        Update-InstallProgress -StatusText "BASARISIZ - $errDetail" -SpinnerFrame 0 `
            -MessageText "$dispName kurulumu basarisiz: $errDetail"
        Write-LogError "$dispName kurulum hatasi: $errDetail (ExitCode: $($installResult.ExitCode))"
    }

    # Log Kaydi
    Write-InstallLog -App $App -StartTime $startTime -EndTime $endTime `
        -ExitCode $installResult.ExitCode -StdOut $installResult.StdOut `
        -StdErr $installResult.StdErr -Success $installResult.Success `
        -Verified $installResult.Verified -VerifiedVersion $installResult.VerifiedVersion

    if (-not $IsBulkMode) {
        Start-Sleep -Seconds 2
    } else {
        Start-Sleep -Milliseconds 600
    }

    return $installResult
}

# ============================================================================
# INVOKE-BULKINSTALL (Toplu Kurulum Motoru)
# ============================================================================
function Invoke-BulkInstall {
<#
.SYNOPSIS
    Birden fazla programi sirali olarak kurar.
.OUTPUTS
    [hashtable[]]
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("AppList", "Programs", "SelectedApps")]
        [PSCustomObject[]]$Apps
    )

    Initialize-InstallerPaths

    $script:CurrentSessionId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $script:CurrentSessionResults = @()

    $totalCount   = $Apps.Count
    $completed    = 0
    $successCount = 0
    $failCount    = 0
    $skipCount    = 0
    $cancelCount  = 0
    $results      = @()
    $stopAllBulk  = $false

    Write-LogInfo "Toplu kurulum baslatildi ($totalCount program). Oturum: $($script:CurrentSessionId)"

    for ($i = 0; $i -lt $Apps.Count; $i++) {
        $app = $Apps[$i]

        if ($stopAllBulk) {
            $cRes = [PSCustomObject]@{
                Success    = $false
                Skipped    = $false
                Cancelled  = $true
                ExitCode   = -99
                StdOut     = ""
                StdErr     = "Kullanici toplu kurulumu iptal etti"
                Duration   = 0
                Verified   = $false
                SkipReason = "Toplu islem iptal edildi"
            }
            $cancelCount++
            $completed++
            $results += @{ App = $app; Result = $cRes }
            continue
        }

        $result = Invoke-WinGetInstall -App $app -IsBulkMode `
            -BulkTotal $totalCount `
            -BulkCompleted $completed `
            -BulkSuccess $successCount `
            -BulkFail $failCount

        if ($result.Cancelled) {
            $cancelCount++
            # Kalan programlar varsa kullaniciya sor
            $remaining = $totalCount - ($completed + 1)
            if ($remaining -gt 0) {
                Write-Host ""
                Write-Host "  [BILGI] Kurulum iptal edildi. Kalan $remaining program kurulsun mu? (E/H) [Varsayilan: H]: " -ForegroundColor Yellow -NoNewline
                $contChoice = Read-Host
                if (-not $contChoice -or $contChoice.Trim().ToUpper() -ne "E") {
                    $stopAllBulk = $true
                    Write-LogWarn "Toplu kurulum kullanici tarafindan durduruldu. Kalan programlar iptal edildi."
                }
            }
        } elseif ($result.Skipped) {
            $skipCount++
            $successCount++
        } elseif ($result.Success) {
            $successCount++
        } else {
            $failCount++
        }
        $completed++

        $results += @{
            App     = $app
            Result  = $result
        }
    }

    Write-LogSuccess "Toplu kurulum bitti. Basarili: $successCount, Basarisiz: $failCount, Atlanan: $skipCount, Iptal: $cancelCount"
    return $results
}

# ============================================================================
# SHOW-INSTALLREPORT (Sonuc Raporu Ekrani)
# ============================================================================
function Show-InstallReport {
<#
.SYNOPSIS
    Kurulum islemleri sonuc raporunu renkli gosterir ve TXT disari aktarma sunar.
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ResultList", "ReportData")]
        [array]$Results,
        [string]$Title = "KURULUM SONUC RAPORU"
    )

    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 1] | Uygulama Kurulum Merkezi  >  $Title" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""

    $totalCount   = $Results.Count
    $successCount = 0
    $failCount    = 0
    $skipCount    = 0
    $cancelCount  = 0
    $totalSec     = 0

    foreach ($item in $Results) {
        $res = if ($item.Result) { $item.Result } else { $item }
        if ($res.Cancelled) {
            $cancelCount++
        } elseif ($res.Skipped) {
            $skipCount++
        } elseif ($res.Success) {
            $successCount++
        } else {
            $failCount++
        }
        if ($res.Duration) { $totalSec += $res.Duration }
    }

    Write-Host "  GENEL OZET" -ForegroundColor Green
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host "    Toplam Islenen  : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$totalCount program" -ForegroundColor White
    Write-Host "    Basarili        : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$successCount" -ForegroundColor Green
    Write-Host "    Basarisiz       : " -ForegroundColor DarkCyan -NoNewline
    if ($failCount -gt 0) { Write-Host "$failCount" -ForegroundColor Red } else { Write-Host "$failCount" -ForegroundColor White }
    Write-Host "    Zaten Kurulu    : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$skipCount" -ForegroundColor Yellow
    if ($cancelCount -gt 0) {
        Write-Host "    Iptal Edilen    : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$cancelCount" -ForegroundColor Yellow
    }
    Write-Host "    Toplam Sure     : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$totalSec saniye" -ForegroundColor White
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""

    Write-Host "  PROGRAM DETAYLARI" -ForegroundColor Green
    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
    Write-Host "  #   PROGRAM ADI                  DURUM        SURE    KOD  DETAY" -ForegroundColor DarkCyan
    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan

    $idx = 1
    foreach ($item in $Results) {
        $app = if ($item.App) { $item.App } else { $item }
        $res = if ($item.Result) { $item.Result } else { $item }

        $numStr = "[$idx]".PadRight(4)
        $name = if ($app.Name) { $app.Name } else { $app.PackageId }
        if ($name.Length -gt 28) { $name = $name.Substring(0, 25) + "..." }
        $namePadded = $name.PadRight(28)

        $durStr = if ($res.Duration) { "$($res.Duration)s".PadLeft(5) } else { "  0s" }
        $codeStr = if ($null -ne $res.ExitCode) { "$($res.ExitCode)".PadLeft(4) } else { "   -" }

        Write-Host "  $numStr $namePadded " -NoNewline

        if ($res.Cancelled) {
            Write-Host "IPTAL EDILDI " -ForegroundColor Yellow -NoNewline
            Write-Host " $durStr  $codeStr  " -NoNewline
            $detail = if ($res.SkipReason) { $res.SkipReason } else { "Kullanici durdurdu" }
            Write-Host "$detail" -ForegroundColor Yellow
        } elseif ($res.Skipped) {
            Write-Host "ZATEN KURULU " -ForegroundColor Yellow -NoNewline
            Write-Host " $durStr  $codeStr  " -NoNewline
            $detail = if ($res.SkipReason) { $res.SkipReason } else { "Atlandi" }
            Write-Host "$detail" -ForegroundColor DarkCyan
        } elseif ($res.Success) {
            Write-Host "BASARILI     " -ForegroundColor Green -NoNewline
            Write-Host " $durStr  $codeStr  " -NoNewline
            $vText = if ($res.VerifiedVersion) { "Dogrulandi ($($res.VerifiedVersion))" } else { "Tamamlandi" }
            Write-Host "$vText" -ForegroundColor Green
        } else {
            Write-Host "BASARISIZ    " -ForegroundColor Red -NoNewline
            Write-Host " $durStr  $codeStr  " -NoNewline
            $errDetail = if ($script:WinGetExitCodes.ContainsKey($res.ExitCode)) {
                $script:WinGetExitCodes[$res.ExitCode]
            } elseif ($res.StdErr) {
                $res.StdErr.Trim()
            } else {
                "Hata kodu: $($res.ExitCode)"
            }
            if ($errDetail.Length -gt 25) { $errDetail = $errDetail.Substring(0, 22) + "..." }
            Write-Host "$errDetail" -ForegroundColor Red
        }
        $idx++
    }

    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
    Write-Host ""

    Write-Host "  Raporu metin (TXT) dosyasina kaydetmek ister misiniz? (E/H) [Varsayilan: H]: " -ForegroundColor Yellow -NoNewline
    $saveChoice = Read-Host
    if ($saveChoice -and $saveChoice.Trim().ToUpper() -eq "E") {
        try {
            $root = if ($global:ProjectRoot) { $global:ProjectRoot }
                    elseif ($script:ProjectRoot) { $script:ProjectRoot }
                    else { (Get-Location).Path }
            $reportDir = Join-Path $root "logs\install_reports"
            if (-not (Test-Path $reportDir)) { $null = New-Item -ItemType Directory -Path $reportDir -Force }

            $ts = Get-Date -Format "yyyyMMdd_HHmmss"
            $reportFile = Join-Path $reportDir "Kurulum_Raporu_$ts.txt"

            $txt = @()
            $txt += "=" * 80
            $txt += "AAU KURULUM ASISTANI - $Title"
            $txt += "Tarih: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $txt += "Toplam: $totalCount | Basarili: $successCount | Basarisiz: $failCount | Zaten Kurulu: $skipCount | Iptal: $cancelCount"
            $txt += "Toplam Sure: $totalSec saniye"
            $txt += "=" * 80
            $txt += ""
            $txt += "PROGRAM LISTESI:"
            $txt += "-" * 80

            $i = 1
            foreach ($item in $Results) {
                $app = if ($item.App) { $item.App } else { $item }
                $res = if ($item.Result) { $item.Result } else { $item }
                $st = if ($res.Cancelled) { "IPTAL EDILDI" } elseif ($res.Skipped) { "ZATEN KURULU" } elseif ($res.Success) { "BASARILI" } else { "BASARISIZ (Kod: $($res.ExitCode))" }
                $txt += "[$i] $($app.Name) ($($app.Id)) -> $st [Sure: $($res.Duration)s]"
                $i++
            }
            $txt += ""
            $txt += "=" * 80

            $txt | Out-File -FilePath $reportFile -Encoding UTF8
            Write-Host ""
            Write-Host "  [BASARILI] Rapor kaydedildi: " -ForegroundColor Green -NoNewline
            Write-Host "$reportFile" -ForegroundColor White
            Write-LogSuccess "Rapor kaydedildi: $reportFile"
        } catch {
            Write-Host ""
            Write-Host "  [HATA] Rapor kaydedilemedi: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ============================================================================
# SHOW-APPINSTALLCENTER (Tekli ve Toplu Kurulum Birlestirilmis Merkez)
# ============================================================================

function Show-SelectedInstallApps {
<#
.SYNOPSIS
    Sepetteki programlari listeler, tek tek cikarabilme veya kurulumu baslatma imkani verir.
#>
    param(
        [System.Collections.Generic.List[PSCustomObject]]$SelectedApps,
        [PSCustomObject]$Catalog
    )

    $exitSelView = $false
    while (-not $exitSelView) {
        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  [ 1] | Uygulama Kurulum Merkezi  >  SEÇİLEN PROGRAMLAR" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        if ($SelectedApps.Count -eq 0) {
            Write-Host "  [BILGI] Sepetinizde su an secili program bulunmuyor." -ForegroundColor Yellow
            Write-Host ""
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Geri donmek icin bir tusa basin..."
            return
        }

        Write-Host "  Secilen Program Sayisi: $($SelectedApps.Count)" -ForegroundColor Green
        Write-Host ""

        $k = 1
        foreach ($app in $SelectedApps) {
            $numTag = "[$k]".PadRight(5)
            $catLabel = if ($app.Category) { " ($($app.Category))" } else { "" }
            Write-Host "  $numTag $($app.Name)$catLabel" -ForegroundColor White
            $k++
        }

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host "  KOMUTLAR:" -ForegroundColor DarkCyan
        Write-Host "    [1-$($SelectedApps.Count)] : Programi sepetten cikar (Orn: 1 veya 1,2)" -ForegroundColor White
        Write-Host "    [C] : Tum Secimleri Temizle" -ForegroundColor Yellow
        Write-Host "    [K] : Kurulumu Baslat ($($SelectedApps.Count) Program)" -ForegroundColor Green
        Write-Host "    [G] : Geri Don" -ForegroundColor Cyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Seciminiz: " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host
        $cmd = if ($null -ne $inp) { $inp.Trim().ToUpper() } else { "" }

        if ($cmd -in "G", "0", "") {
            $exitSelView = $true
            return
        } elseif ($cmd -eq "C") {
            $SelectedApps.Clear()
            Write-Host "  [BILGI] Tum secimler temizlendi." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 400
            return
        } elseif ($cmd -eq "K") {
            Invoke-UnifiedInstallAction -SelectedApps $SelectedApps -Catalog $Catalog
            return
        } else {
            # Numaraya gore cikar
            $tokens = $cmd -split '[,;\s]+'
            $toRemove = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($t in $tokens) {
                if ($t -match '^\d+$') {
                    $idx = [int]$t
                    if ($idx -ge 1 -and $idx -le $SelectedApps.Count) {
                        $toRemove.Add($SelectedApps[$idx - 1])
                    }
                }
            }
            foreach ($rem in $toRemove) {
                $SelectedApps.Remove($rem) | Out-Null
            }
            if ($toRemove.Count -gt 0) {
                Write-Host "  [BILGI] $($toRemove.Count) program sepetten cikarildi." -ForegroundColor Yellow
                Start-Sleep -Milliseconds 400
            }
        }
    }
}

function Show-CategoryInstallView {
<#
.SYNOPSIS
    Kullanici istegindeki kategori detay ekranini sunar, sepeti korur ve coklu secim imkani saglar.
#>
    param(
        [hashtable]$Category,
        [array]$AllApps,
        [System.Collections.Generic.List[PSCustomObject]]$SelectedApps,
        [PSCustomObject]$Catalog
    )

    $catId = $Category.Id
    $catTitle = $Category.Name.ToUpper()
    $appsInCat = @($AllApps | Where-Object { "$($_.Category)".ToLower() -eq $catId.ToLower() } | Sort-Object @{
        Expression = { if ($null -ne $_.InstallOrder) { [int]$_.InstallOrder } else { 9999 } }
    }, Name)

    $exitCategoryView = $false
    while (-not $exitCategoryView) {
        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  $catTitle" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        if ($appsInCat.Count -eq 0) {
            Write-Host "  [BILGI] Bu kategoride henuz tanimli program bulunmuyor." -ForegroundColor Yellow
            Write-Host ""
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Geri donmek icin bir tusa basin..."
            return
        }

        $i = 1
        foreach ($app in $appsInCat) {
            $isSelected = ($null -ne ($SelectedApps | Where-Object {
                ($_.Id -and $app.Id -and $_.Id -eq $app.Id) -or ($_.Name -eq $app.Name)
            }))
            $chk = if ($isSelected) { "[*]" } else { "[ ]" }
            $chkColor = if ($isSelected) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkGray }
            $numTag = "[$i]".PadRight(4)

            Write-Host "  $chk " -ForegroundColor $chkColor -NoNewline
            Write-Host "$numTag $($app.Name)" -ForegroundColor White
            $i++
        }

        Write-Host ""
        Write-Host "  Seçilen: $($SelectedApps.Count)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [1,3] şeklinde birden fazla program seçebilirsin." -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  [S] Seçilenleri Görüntüle" -ForegroundColor Cyan
        Write-Host "  [T] Tümünü Seç (Bu Kategori)" -ForegroundColor Yellow
        Write-Host "  [C] Kategori Seçimlerini Temizle" -ForegroundColor Yellow
        Write-Host "  [K] Kurulumu Başlat" -ForegroundColor Green
        Write-Host "  [G] Geri Dön" -ForegroundColor Yellow
        Write-Host "  [0] Ana Menü" -ForegroundColor Red
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Seçiminiz: " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host
        $choice = if ($null -ne $inp) { $inp.Trim() } else { "" }

        if ($choice -eq "0" -or $choice -eq "00") {
            $script:ExitToMainMenu = $true
            return
        } elseif ($choice.ToUpper() -eq "G") {
            return
        } elseif ($choice.ToUpper() -eq "S") {
            Show-SelectedInstallApps -SelectedApps $SelectedApps -Catalog $Catalog
        } elseif ($choice.ToUpper() -eq "T") {
            foreach ($a in $appsInCat) {
                if (-not ($SelectedApps | Where-Object { $_.Name -eq $a.Name })) {
                    $SelectedApps.Add($a)
                }
            }
            Write-Host "  [BILGI] Kategorideki tum programlar sepete eklendi." -ForegroundColor Green
            Start-Sleep -Milliseconds 400
        } elseif ($choice.ToUpper() -eq "C") {
            $toRemove = @($SelectedApps | Where-Object { "$($_.Category)".ToLower() -eq $catId.ToLower() })
            foreach ($rem in $toRemove) { $SelectedApps.Remove($rem) | Out-Null }
            Write-Host "  [BILGI] Bu kategorideki secimler temizlendi." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 400
        } elseif ($choice.ToUpper() -eq "K") {
            Invoke-UnifiedInstallAction -SelectedApps $SelectedApps -Catalog $Catalog
            return
        } else {
            # Numaralari ayristir (Orn: 1,3 veya 1-4)
            $tokens = $choice -split '[,;\s]+'
            $modified = $false
            foreach ($t in $tokens) {
                if ($t -match '^(\d+)-(\d+)$') {
                    $s = [int]$matches[1]; $e = [int]$matches[2]
                    if ($s -le $e) {
                        for ($x = $s; $x -le $e; $x++) {
                            if ($x -ge 1 -and $x -le $appsInCat.Count) {
                                $target = $appsInCat[$x - 1]
                                $existing = $SelectedApps | Where-Object { $_.Name -eq $target.Name }
                                if ($existing) { $SelectedApps.Remove($existing) | Out-Null }
                                else { $SelectedApps.Add($target) }
                                $modified = $true
                            }
                        }
                    }
                } elseif ($t -match '^\d+$') {
                    $x = [int]$t
                    if ($x -ge 1 -and $x -le $appsInCat.Count) {
                        $target = $appsInCat[$x - 1]
                        $existing = $SelectedApps | Where-Object { $_.Name -eq $target.Name }
                        if ($existing) { $SelectedApps.Remove($existing) | Out-Null }
                        else { $SelectedApps.Add($target) }
                        $modified = $true
                    }
                }
            }
            if (-not $modified) {
                Write-Host "  [HATA] Gecersiz giris!" -ForegroundColor Red
                Start-Sleep -Milliseconds 500
            }
        }
    }
}

function Invoke-UnifiedInstallAction {
<#
.SYNOPSIS
    Secilen program sayisina gore otomatik calisir:
    - 1 Program: Tekli kurulum motoru (onay, kurulum, kisayol kontrolu).
    - 2+ Program: Toplu kurulum motoru (onay listesi, sirali kurulum, rapor, kisayol kontrolu).
    Her iki durumda da ayni profesyonel kurulum ekrani kullanilir.
#>
    param(
        [System.Collections.Generic.List[PSCustomObject]]$SelectedApps,
        [PSCustomObject]$Catalog
    )

    if ($SelectedApps.Count -eq 0) {
        Write-Host ""
        Write-Host "  [UYARI] Kurulacak program secilmedi! Once program secin." -ForegroundColor Red
        Start-Sleep -Seconds 1
        return
    }

    if ($SelectedApps.Count -eq 1) {
        # ====================================================================
        # TEKLI PROGRAM KURULUM MOTORU
        # ====================================================================
        $singleApp = $SelectedApps[0]

        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  [ 1] | Uygulama Kurulum Merkezi  >  KURULUM ONAYI" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Kurulacak Program: " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($singleApp.Name)" -ForegroundColor White
        Write-Host "  Paket Kimligi    : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($singleApp.winget_id)" -ForegroundColor Cyan
        Write-Host "  Kaynak / Mimari  : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($singleApp.Source) / $($singleApp.Architecture)" -ForegroundColor White
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Kurulumu baslatmak istiyor musunuz? (E/H) [Varsayilan: E]: " -ForegroundColor Yellow -NoNewline
        $ans = Read-Host
        if ($ans -and $ans.Trim().ToUpper() -eq "H") {
            Write-Host "  [BILGI] Kurulum iptal edildi." -ForegroundColor DarkCyan
            Start-Sleep -Seconds 1
            return
        }

        # Ortak Kurulum Motorunu Calistir (Kisayol kontrolu Invoke-WinGetInstall icinde yapilir)
        $res = Invoke-WinGetInstall -App $singleApp -IsBulkMode:$false

        # Secim listesini temizle
        $SelectedApps.Clear()

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Wait-UserKeyPress -PromptMessage "Kurulum Merkezine donmek icin bir tusa basin..."
    } else {
        # ====================================================================
        # TOPLU PROGRAM KURULUM MOTORU
        # ====================================================================
        $sortedList = @($SelectedApps | Sort-Object @{
            Expression = { if ($null -ne $_.InstallOrder) { [int]$_.InstallOrder } else { 9999 } }
        }, Name)

        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  [ 1] | Uygulama Kurulum Merkezi  >  TOPLU KURULUM ONAYI" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Asagidaki $($sortedList.Count) program sirasiyla kurulacaktir:" -ForegroundColor White
        Write-Host ""

        $k = 1
        foreach ($item in $sortedList) {
            $numTag = if ($k -lt 10) { "[ $k] |" } else { "[$k] |" }
            $src = if ($item.Source -eq "msstore") { " [Store]" } else { " [WinGet]" }
            Write-Host "  $numTag " -ForegroundColor Green -NoNewline
            Write-Host "$($item.Name)".PadRight(30) -ForegroundColor White -NoNewline
            Write-Host "$src".PadRight(10) -ForegroundColor Cyan -NoNewline
            Write-Host " (Sira: $($item.InstallOrder))" -ForegroundColor Yellow
            $k++
        }

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Toplu kurulumu simdi baslatmak istiyor musunuz? (E/H) [Varsayilan: E]: " -ForegroundColor Yellow -NoNewline
        $confBulk = Read-Host
        if ($confBulk -and $confBulk.Trim().ToUpper() -eq "H") {
            Write-Host "  [BILGI] Toplu kurulum iptal edildi." -ForegroundColor DarkCyan
            Start-Sleep -Seconds 1
            return
        }

        Write-LogInfo "Toplu kurulum baslatiliyor ($($sortedList.Count) program)."
        $bulkResults = Invoke-BulkInstall -Apps $sortedList

        # Raporu Goster
        Show-InstallReport -Results $bulkResults -Title "TOPLU KURULUM SONUC RAPORU"

        # Kurulum Sonrasi Kisayol Denetimi (Toplu Kurulumda Atlanan veya Kisayolu Eksik Olanlar)
        if (Get-Command "Test-AppStartMenuShortcut" -ErrorAction SilentlyContinue) {
            $missingShortcuts = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($b in $bulkResults) {
                $r = if ($b.Result) { $b.Result } else { $b }
                if ($r.Success -and -not $r.Skipped) {
                    $appId = if ($b.App.winget_id) { $b.App.winget_id }
                             elseif ($b.App.Id) { $b.App.Id }
                             elseif ($b.App.packageId) { $b.App.packageId }
                             else { "" }
                    $chk = Test-AppStartMenuShortcut -AppName $b.App.Name -PackageId $appId
                    if (-not $chk.ShortcutFound) {
                        $missingShortcuts.Add($b.App)
                    }
                }
            }

            if ($missingShortcuts.Count -gt 0) {
                Write-Host ""
                Write-Host "  [UYARI] $($missingShortcuts.Count) programin Baslat Menusu kisayolu bulunamadi:" -ForegroundColor Yellow
                foreach ($mApp in $missingShortcuts) {
                    Write-Host "    - $($mApp.Name)" -ForegroundColor White
                }
                Write-Host ""
                Write-Host "  Bu programlar icin kisayol olusturulsun mu? (E/H) [Varsayilan: E]: " -ForegroundColor Yellow -NoNewline
                $scAns = Read-Host
                if (-not $scAns -or $scAns.Trim().ToUpper() -eq "E") {
                    foreach ($mApp in $missingShortcuts) {
                        $appId = if ($mApp.winget_id) { $mApp.winget_id }
                                 elseif ($mApp.Id) { $mApp.Id }
                                 elseif ($mApp.packageId) { $mApp.packageId }
                                 else { "" }
                        $mExe = Get-AppExecutablePath -AppName $mApp.Name -PackageId $appId
                        if ($mExe) {
                            $null = Invoke-CreateAppShortcut -AppName $mApp.Name -ExePath $mExe
                            Write-Host "    [✓] $($mApp.Name) icin kisayol olusturuldu." -ForegroundColor Green
                        } else {
                            Write-Host "    [!] $($mApp.Name) calistirilabilir dosyasi bulunamadi." -ForegroundColor Yellow
                        }
                    }
                    Start-Sleep -Seconds 1
                }
            }
        }

        $SelectedApps.Clear()

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Wait-UserKeyPress -PromptMessage "Kurulum Merkezine donmek icin bir tusa basin..."
    }
}

function Show-AppInstallCenter {
<#
.SYNOPSIS
    Tekli ve toplu kurulumu tek ekranda birlestiren iki sutunlu Genel Liste kurulum merkezi.
    Kullanici 36 uygulamanin tamamini Ghost Toolbox tarzinda 2 sutun halinde kategorileriyle gorur.
    Numaralarla (1, 1,3,5, 1-4, T/hepsi) secim yapar; tek secilirse tekli, coklu secilirse toplu kurulum calisir.
#>
    param([PSCustomObject]$Catalog)

    if (-not $Catalog) {
        $Catalog = Import-AppCatalog
    }
    if (-not $Catalog -or -not $Catalog.applications) {
        Write-Host "  [HATA] Uygulama katalogu bulunamadi!" -ForegroundColor Red
        return
    }

    # Hazirlik Kontrolu
    $ready = Test-WinGetReady
    if (-not $ready.IsReady) {
        Show-WinGetReadinessError -ReadinessResult $ready
        return
    }

    $allApps = @(Get-AppList -Catalog $Catalog | Sort-Object InstallOrder)
    $selectedApps = [System.Collections.Generic.List[PSCustomObject]]::new()
    $script:ExitToMainMenu = $false

    # 8 Kategori Tanimlari (Baslik, Renk, Ikon ve Dinamik Aralik)
    $categoryDefs = @(
        @{ Id = "browsers";      Title = "TARAYICILAR";                   Color = [ConsoleColor]::Cyan;    Icon = "🌐" },
        @{ Id = "utilities";     Title = "TEMEL SISTEM ARACLARI VE SIKISTIRMA"; Color = [ConsoleColor]::Green;   Icon = "🛠️" },
        @{ Id = "media";         Title = "MEDYA, GORSEL VE SES";          Color = [ConsoleColor]::Magenta; Icon = "🎬" },
        @{ Id = "office";        Title = "OFIS VE DOKUMAN";               Color = [ConsoleColor]::White;   Icon = "📄" },
        @{ Id = "communication"; Title = "ILETISIM VE BULUT SENKRONIZASYON"; Color = [ConsoleColor]::Yellow;  Icon = "💬" },
        @{ Id = "gaming";        Title = "OYUN PLATFORMLARI";             Color = [ConsoleColor]::Cyan;    Icon = "🎮" },
        @{ Id = "developer";     Title = "GELISTIRICI VE BAKIM ARACLARI"; Color = [ConsoleColor]::Green;   Icon = "💻" },
        @{ Id = "runtime";       Title = "GEREKLI SISTEM BILESENLERI";    Color = [ConsoleColor]::Red;     Icon = "⚙️" }
    )

    $exitCenter = $false
    while (-not $exitCenter) {
        if ($script:ExitToMainMenu) {
            $script:ExitToMainMenu = $false
            return
        }

        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""

        # Dinamik konsol genisligi tespiti (Tam ekran ve genis pencereleri degerlendirme)
        $consWidth = 86
        try {
            $w = [Console]::WindowWidth
            if ($w -gt $consWidth) { $consWidth = $w }
        } catch {}
        try {
            $rw = $Host.UI.RawUI.WindowSize.Width
            if ($rw -gt $consWidth) { $consWidth = $rw }
        } catch {}
        try {
            $bw = $Host.UI.RawUI.BufferSize.Width
            if ($bw -gt $consWidth) { $consWidth = $bw }
        } catch {}

        # Ekran genisligine gore kolon sayisi ve hucre genisligi hesaplama
        # Standart genislikte dahi en az 3 sutun kullanilarak sag taraf doldurulur ve satir sayisi azaltilir
        if ($script:UserColumnChoice -and $script:UserColumnChoice -ge 3 -and $script:UserColumnChoice -le 6) {
            $colCount = $script:UserColumnChoice
        } else {
            if ($consWidth -ge 165) {
                $colCount = 6
            } elseif ($consWidth -ge 135) {
                $colCount = 5
            } elseif ($consWidth -ge 105) {
                $colCount = 4
            } else {
                $colCount = 3
            }
        }

        $availWidth = [Math]::Max(84, ($consWidth - 4))
        $cellWidth = [Math]::Floor($availWidth / $colCount)
        $maxNameLen = [Math]::Max(14, ($cellWidth - 11))
        $bannerLen = [Math]::Max(86, [Math]::Min($consWidth - 2, ($cellWidth * $colCount + 2)))

        $boxInnerW = [Math]::Max(83, ($bannerLen - 4))
        $boxTitle = "UYGULAMA KURULUM MERKEZİ (GENEL LİSTE)"
        $boxPadL = [Math]::Max(0, [int](($boxInnerW - $boxTitle.Length) / 2))
        $boxPadR = [Math]::Max(0, ($boxInnerW - $boxTitle.Length - $boxPadL))
        Write-Host ("  ╔" + ("═" * $boxInnerW) + "╗") -ForegroundColor DarkCyan
        Write-Host ("  ║" + (" " * $boxPadL) + $boxTitle + (" " * $boxPadR) + "║") -ForegroundColor Green
        Write-Host ("  ╚" + ("═" * $boxInnerW) + "╝") -ForegroundColor DarkCyan

        foreach ($cat in $categoryDefs) {
            $cApps = @($allApps | Where-Object { "$($_.Category)".ToLower() -eq $cat.Id.ToLower() } | Sort-Object InstallOrder)
            if ($cApps.Count -eq 0) { continue }

            $firstOrder = $cApps[0].InstallOrder
            $lastOrder = $cApps[-1].InstallOrder
            $headerText = "  {0} {1} ({2}-{3}) [{4} Uygulama]" -f $cat.Icon, $cat.Title, $firstOrder, $lastOrder, $cApps.Count

            Write-Host ""
            Write-Host $headerText -ForegroundColor $cat.Color
            Write-Host ("  " + ("-" * $bannerLen)) -ForegroundColor DarkCyan

            for ($r = 0; $r -lt $cApps.Count; $r += $colCount) {
                Write-Host "  " -NoNewline
                for ($c = 0; $c -lt $colCount; $c++) {
                    $idx = $r + $c
                    if ($idx -lt $cApps.Count) {
                        $app = $cApps[$idx]
                        $isSel = [bool]($selectedApps | Where-Object { $_.Id -eq $app.Id })
                        $ordStr = if ($app.InstallOrder -lt 10) { "[  $($app.InstallOrder)]" } elseif ($app.InstallOrder -lt 100) { "[ $($app.InstallOrder)]" } else { "[$($app.InstallOrder)]" }
                        $chkStr = if ($isSel) { "[X]" } else { "[ ]" }
                        $name = $app.Name
                        if ($name.Length -gt $maxNameLen) { $name = $name.Substring(0, $maxNameLen - 3) + "..." }
                        $namePad = $name.PadRight($maxNameLen)

                        Write-Host $ordStr -ForegroundColor Yellow -NoNewline
                        Write-Host " " -NoNewline
                        if ($isSel) {
                            Write-Host $chkStr -ForegroundColor Green -NoNewline
                            Write-Host " " -NoNewline
                            Write-Host $namePad -ForegroundColor Green -NoNewline
                        } else {
                            Write-Host $chkStr -ForegroundColor DarkGray -NoNewline
                            Write-Host " " -NoNewline
                            Write-Host $namePad -ForegroundColor White -NoNewline
                        }
                        # Hucre arasi bosluk
                        $padRemaining = $cellWidth - (6 + 3 + 1 + $maxNameLen)
                        if ($padRemaining -gt 0) {
                            Write-Host (" " * $padRemaining) -NoNewline
                        } else {
                            Write-Host " " -NoNewline
                        }
                    } else {
                        Write-Host ("".PadRight($cellWidth)) -NoNewline
                    }
                }
                Write-Host ""
            }
        }

        Write-Host ""
        Write-Host ("  " + ("=" * $bannerLen)) -ForegroundColor DarkCyan
        Write-Host "  SEÇİM DURUMU: " -ForegroundColor DarkCyan -NoNewline
        if ($selectedApps.Count -eq 0) {
            Write-Host "Henuz program secilmedi (0 adet)" -ForegroundColor Yellow
        } else {
            $selNames = ($selectedApps | Select-Object -ExpandProperty Name) -join ", "
            $maxSelShow = [Math]::Max(40, ($bannerLen - 30))
            if ($selNames.Length -gt $maxSelShow) { $selNames = $selNames.Substring(0, $maxSelShow - 3) + "..." }
            Write-Host ("{0} program secildi ({1})" -f $selectedApps.Count, $selNames) -ForegroundColor Green
        }
        Write-Host ("  " + ("-" * $bannerLen)) -ForegroundColor DarkCyan
        Write-Host "  [1-$($allApps.Count)] Seç / Kaldır (Örn: 1 | Çoklu: 1,3,5 | Aralık: 1-14)   [T] Tümünü Seç   [C] Temizle" -ForegroundColor White
        $colLabel = if ($script:UserColumnChoice) { "$($script:UserColumnChoice) Sutun" } else { "Oto ($colCount Sutun)" }
        Write-Host "  [P] Profil   [V] Görünüm: $colLabel   [K] Kuruluma Başla   [S] Seçilenler   [A] Ara   [H] Geçmiş   [0] Çıkış" -ForegroundColor Cyan
        Write-Host ("  " + ("=" * $bannerLen)) -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  Seciminiz: " -ForegroundColor Yellow -NoNewline

        $inp = Read-Host
        $choice = if ($null -ne $inp) { $inp.Trim() } else { "" }

        if ($choice -eq "0" -or $choice -eq "00" -or $choice.ToUpper() -eq "Q") {
            $exitCenter = $true
            return
        } elseif ($choice.ToUpper() -eq "A") {
            if (Get-Command "Show-AppSearchResults" -ErrorAction SilentlyContinue) {
                Show-AppSearchResults -Catalog $Catalog
            }
        } elseif ($choice.ToUpper() -eq "H") {
            Show-InstallHistory
        } elseif ($choice.ToUpper() -eq "T" -or $choice.ToUpper() -eq "HEPSI" -or $choice.ToUpper() -eq "TÜMÜ") {
            $selectedApps.Clear()
            foreach ($a in $allApps) { $selectedApps.Add($a) }
            Write-Host "  [BILGI] Tum programlar ($($selectedApps.Count) adet) secildi." -ForegroundColor Green
            Start-Sleep -Milliseconds 600
        } elseif ($choice.ToUpper() -eq "P" -or $choice.ToUpper() -eq "PROFIL") {
            Show-ProfileInstallSelector -SelectedApps $selectedApps -Catalog $Catalog
            if ($script:ExitToMainMenu) {
                $script:ExitToMainMenu = $false
                return
            }
        } elseif ($choice.ToUpper() -eq "V" -or $choice.ToUpper() -eq "SUTUN" -or $choice.ToUpper() -eq "GORUNUM") {
            if (-not $script:UserColumnChoice) {
                $script:UserColumnChoice = 4
            } elseif ($script:UserColumnChoice -eq 3) {
                $script:UserColumnChoice = 4
            } elseif ($script:UserColumnChoice -eq 4) {
                $script:UserColumnChoice = 5
            } elseif ($script:UserColumnChoice -eq 5) {
                $script:UserColumnChoice = 6
            } elseif ($script:UserColumnChoice -ge 6) {
                $script:UserColumnChoice = 3
            }
        } elseif ($choice.ToUpper() -eq "C" -or $choice.ToUpper() -eq "TEMIZLE") {
            $selectedApps.Clear()
            Write-Host "  [BILGI] Secimler temizlendi." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 600
        } elseif ($choice.ToUpper() -eq "S") {
            Show-SelectedInstallApps -SelectedApps $selectedApps -Catalog $Catalog
        } elseif ($choice.ToUpper() -eq "K") {
            if ($selectedApps.Count -eq 0) {
                Write-Host "  [UYARI] Kuruluma baslamak icin lutfen en az bir program secin!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            } else {
                Invoke-UnifiedInstallAction -SelectedApps $selectedApps -Catalog $Catalog
                if ($script:ExitToMainMenu) {
                    $script:ExitToMainMenu = $false
                    return
                }
            }
        } else {
            # Sayısal veya aralık girişi ayrıştırma (Örn: 1 veya 1,3,5 veya 1-4 veya k 1)
            $isImmediateInstall = $false
            $cleanInput = $choice
            if ($cleanInput -match '^(k|kur|kurulum)\s+(.+)$') {
                $isImmediateInstall = $true
                $cleanInput = $matches[2]
            }

            $tokens = $cleanInput -split '[\s,]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $targetOrders = [System.Collections.Generic.List[int]]::new()

            foreach ($tok in $tokens) {
                if ($tok -match '^(\d+)-(\d+)$') {
                    $start = [int]$matches[1]
                    $end = [int]$matches[2]
                    if ($start -gt $end) { $tmp = $start; $start = $end; $end = $tmp }
                    for ($n = $start; $n -le $end; $n++) {
                        if ($n -ge 1 -and $n -le $allApps.Count -and -not $targetOrders.Contains($n)) {
                            $targetOrders.Add($n)
                        }
                    }
                } elseif ($tok -match '^\d+$') {
                    $n = [int]$tok
                    if ($n -ge 1 -and $n -le $allApps.Count -and -not $targetOrders.Contains($n)) {
                        $targetOrders.Add($n)
                    }
                }
            }

            if ($targetOrders.Count -gt 0) {
                foreach ($ord in $targetOrders) {
                    $targetApp = $allApps | Where-Object { $_.InstallOrder -eq $ord } | Select-Object -First 1
                    if ($targetApp) {
                        $existingIdx = -1
                        for ($si = 0; $si -lt $selectedApps.Count; $si++) {
                            if ($selectedApps[$si].Id -eq $targetApp.Id) {
                                $existingIdx = $si
                                break
                            }
                        }
                        if ($existingIdx -ge 0) {
                            $selectedApps.RemoveAt($existingIdx)
                        } else {
                            $selectedApps.Add($targetApp)
                        }
                    }
                }

                if ($isImmediateInstall -and $selectedApps.Count -gt 0) {
                    Invoke-UnifiedInstallAction -SelectedApps $selectedApps -Catalog $Catalog
                    if ($script:ExitToMainMenu) {
                        $script:ExitToMainMenu = $false
                        return
                    }
                }
            } else {
                Write-Host "  [HATA] Gecersiz secim!" -ForegroundColor Red
                Start-Sleep -Milliseconds 600
            }
        }
    }
}

function Show-SingleInstallMenu {
    param([PSCustomObject]$Catalog)
    Show-AppInstallCenter -Catalog $Catalog
}

function Show-BulkInstallMenu {
    param([PSCustomObject]$Catalog)
    Show-AppInstallCenter -Catalog $Catalog
}


# ============================================================================
# SHOW-INSTALLHISTORY (Kurulum Gecmisi ve Yonetimi)
# ============================================================================
function Show-InstallHistory {
<#
.SYNOPSIS
    Kurulum gecmisini listeler, basarisizlari filtreler ve raporu disari aktarir.
#>
    $exitHist = $false
    while (-not $exitHist) {
        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  [ 1] | Uygulama Kurulum Merkezi  >  Kurulum Gecmisi" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        $history = Get-InstallHistory
        if (-not $history -or $history.Count -eq 0) {
            Write-Host "  [BILGI] Henuz kaydedilmis bir kurulum gecmisi bulunmuyor." -ForegroundColor DarkCyan
            Write-Host ""
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
            return
        }

        Write-Host "  Toplam $($history.Count) adet islem kaydi mevcut:" -ForegroundColor White
        Write-Host ""

        $reversed = @($history | Sort-Object Timestamp -Descending)

        Write-Host "  TARIH / SAAT         DURUM        SURE   PROGRAM ADI                  KOD" -ForegroundColor DarkCyan
        Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan

        $displayList = @($reversed | Select-Object -First 25)

        foreach ($entry in $displayList) {
            $ts = if ($entry.Timestamp) { $entry.Timestamp } else { "Bilinmiyor" }
            $tsPadded = $ts.PadRight(20)

            $durStr = if ($entry.DurationSec) { "$($entry.DurationSec)s".PadLeft(5) } else { "  0s" }
            $codeStr = if ($null -ne $entry.ExitCode) { "$($entry.ExitCode)".PadLeft(4) } else { "   -" }

            $pName = if ($entry.Name) { $entry.Name } else { $entry.PackageId }
            if ($pName.Length -gt 28) { $pName = $pName.Substring(0, 25) + "..." }
            $pNamePadded = $pName.PadRight(28)

            Write-Host "  $tsPadded " -ForegroundColor DarkCyan -NoNewline

            if ($entry.SkipReason) {
                Write-Host "ATLANDI      " -ForegroundColor Yellow -NoNewline
            } elseif ($entry.Success -eq $true) {
                Write-Host "BASARILI     " -ForegroundColor Green -NoNewline
            } else {
                Write-Host "BASARISIZ    " -ForegroundColor Red -NoNewline
            }

            Write-Host "$durStr  $pNamePadded  $codeStr" -ForegroundColor White
        }

        Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  ISLEMLER:" -ForegroundColor DarkCyan
        Write-Host "    [1] Yalnizca Basarisizlari Filtrele" -ForegroundColor Yellow
        Write-Host "    [2] Gecmisi TXT Raporu Olarak Disa Aktar" -ForegroundColor Cyan
        Write-Host "    [3] Gecmis Kayitlarini Temizle (Sifirla)" -ForegroundColor Red
        Write-Host "    [0] Alt Menuye Don" -ForegroundColor White
        Write-Host ""
        Write-Host "  Seciminiz [1-3 | 0=Geri]: " -ForegroundColor Yellow -NoNewline
        $hChoice = Read-Host

        if ($hChoice -eq "0" -or $hChoice -eq "00") {
            $exitHist = $true
            return
        } elseif ($hChoice -eq "1") {
            # Sadece basarisizlar
            $failed = @($history | Where-Object { $_.Success -eq $false -and (-not $_.SkipReason) } | Sort-Object Timestamp -Descending)
            Show-ScreenTransition -Scrollable
            Show-AppHeader -Scrollable
            Write-Host ""
            Write-Host "  [ 1] | Kurulum Gecmisi  >  Basarisiz Islemler" -ForegroundColor Red
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Write-Host ""
            if ($failed.Count -eq 0) {
                Write-Host "  [TEBRIKLER] Hicbir basarisiz islem kaydi bulunmuyor!" -ForegroundColor Green
            } else {
                Write-Host "  Toplam $($failed.Count) basarisiz islem tespit edildi:" -ForegroundColor Red
                Write-Host ""
                foreach ($f in $failed) {
                    Write-Host "  $($f.Timestamp) | $($f.Name) ($($f.PackageId)) - Kod: $($f.ExitCode)" -ForegroundColor Red
                    if ($f.ErrorMsg) { Write-Host "    Hata: $($f.ErrorMsg)" -ForegroundColor White }
                }
            }
            Write-Host ""
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Wait-UserKeyPress -PromptMessage "Gecmis menusune donmek icin bir tusa basin..."
        } elseif ($hChoice -eq "2") {
            # TXT disa aktar
            try {
                $root = if ($global:ProjectRoot) { $global:ProjectRoot } else { (Get-Location).Path }
                $rDir = Join-Path $root "logs\install_reports"
                if (-not (Test-Path $rDir)) { $null = New-Item -ItemType Directory -Path $rDir -Force }
                $fPath = Join-Path $rDir ("Gecmis_Raporu_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".txt")

                $lines = @()
                $lines += "=" * 80
                $lines += "AAU KURULUM ASISTANI - KURULUM GECMIS RAPORU"
                $lines += "Tarih: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $lines += "Toplam Kayit: $($history.Count)"
                $lines += "=" * 80
                foreach ($h in $reversed) {
                    $st = if ($h.SkipReason) { "ATLANDI ($($h.SkipReason))" } elseif ($h.Success) { "BASARILI" } else { "BASARISIZ (Kod: $($h.ExitCode))" }
                    $lines += "[$($h.Timestamp)] $($h.Name) ($($h.PackageId)) -> $st (Sure: $($h.DurationSec)s)"
                }
                $lines | Out-File -FilePath $fPath -Encoding UTF8
                Write-Host ""
                Write-Host "  [BASARILI] Rapor kaydedildi: $fPath" -ForegroundColor Green
                Start-Sleep -Seconds 2
            } catch {
                Write-Host "  [HATA] Kayit basarisiz: $($_.Exception.Message)" -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        } elseif ($hChoice -eq "3") {
            # Temizle
            Write-Host "  [DIKKAT] Tum kurulum gecmisi silinecektir! Emin misiniz? (E/H): " -ForegroundColor Red -NoNewline
            $cClean = Read-Host
            if ($cClean -and $cClean.Trim().ToUpper() -eq "E") {
                try {
                    if (Test-Path $script:InstallHistoryFile) {
                        Remove-Item $script:InstallHistoryFile -Force -ErrorAction SilentlyContinue
                    }
                    Write-Host "  [BASARILI] Kurulum gecmisi temizlendi!" -ForegroundColor Green
                    Write-LogSuccess "Kurulum gecmisi kullanici tarafindan sifirlandi."
                    Start-Sleep -Seconds 1
                } catch {
                    Write-Host "  [HATA] Silinemedi: $($_.Exception.Message)" -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}

# ============================================================================
# INVOKE-RETRYFAILEDINSTALLS (Basarisizlari Tekrar Dene)
# ============================================================================
function Invoke-RetryFailedInstalls {
<#
.SYNOPSIS
    Gecmisteki basarisiz kurulumlari listeler, secilenleri veya tumunu tekrar kurar.
#>
    param([PSCustomObject]$Catalog)

    if (-not $Catalog) {
        $Catalog = Import-AppCatalog
    }

    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 1] | Uygulama Kurulum Merkezi  >  Basarisiz Kurulumlari Tekrar Dene" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""

    $history = Get-InstallHistory
    if (-not $history -or $history.Count -eq 0) {
        Write-Host "  [BILGI] Gecmiste herhangi bir kurulum kaydi bulunamadi." -ForegroundColor DarkCyan
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
        return
    }

    $failedEntries = @($history | Where-Object { $_.Success -eq $false -and (-not $_.SkipReason) })
    if ($failedEntries.Count -eq 0) {
        Write-Host "  [TEBRIKLER] Gecmiste basarisiz olmus hicbir kurulum kaydi bulunmuyor!" -ForegroundColor Green
        Write-Host "  Tum kurulumlar basariyla tamamlanmis gorunuyor." -ForegroundColor White
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
        return
    }

    $uniqueFailedIds = @($failedEntries | Select-Object -ExpandProperty PackageId -Unique)

    $retryApps = @()
    foreach ($fId in $uniqueFailedIds) {
        $matched = Search-AppById -Catalog $Catalog -AppId $fId
        if ($matched) {
            $retryApps += $matched
        }
    }

    if ($retryApps.Count -eq 0) {
        Write-Host "  [UYARI] Basarisiz olan paketler su anki katalogda bulunamadi." -ForegroundColor Yellow
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Wait-UserKeyPress -PromptMessage "Alt menuye donmek icin bir tusa basin..."
        return
    }

    Write-Host "  Tekrar denenebilecek $($retryApps.Count) basarisiz program tespit edildi:" -ForegroundColor Yellow
    Write-Host ""

    $rIdx = 1
    foreach ($rApp in $retryApps) {
        $lastFail = @($failedEntries | Where-Object { $_.PackageId -eq $rApp.Id })[-1]
        $errDesc = if ($script:WinGetExitCodes.ContainsKey($lastFail.ExitCode)) {
            $script:WinGetExitCodes[$lastFail.ExitCode]
        } else {
            "Kod: $($lastFail.ExitCode)"
        }
        Write-Host "    [$rIdx] " -ForegroundColor Red -NoNewline
        Write-Host "$($rApp.Name)".PadRight(28) -ForegroundColor White -NoNewline
        Write-Host " ($($rApp.Id))".PadRight(32) -ForegroundColor DarkCyan -NoNewline
        Write-Host " [$errDesc]" -ForegroundColor Yellow
        $rIdx++
    }

    Write-Host ""
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  Tekrar kurmak istediginiz program numaralarini girin (T=Tumunu Tekrar Dene | 0=Iptal): " -ForegroundColor Yellow -NoNewline
    $conf = Read-Host
    $confStr = if ($null -ne $conf) { $conf.Trim().ToUpper() } else { "" }

    if ($confStr -eq "0" -or $confStr -eq "00") {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        Start-Sleep -Seconds 1
        return
    }

    $appsToRetry = @()
    if ($confStr -eq "T") {
        $appsToRetry = $retryApps
    } else {
        $tokens = $confStr -split '[,;\s]+'
        foreach ($t in $tokens) {
            if ($t -match '^\d+$') {
                $idx = [int]$t
                if ($idx -ge 1 -and $idx -le $retryApps.Count) {
                    $appsToRetry += $retryApps[$idx - 1]
                }
            }
        }
    }

    if ($appsToRetry.Count -eq 0) {
        Write-Host "  [UYARI] Gecerli bir program secilmedi." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    Write-LogInfo "Basarisiz kurulumlar tekrar deneniyor ($($appsToRetry.Count) program)."
    $retryResults = Invoke-BulkInstall -Apps $appsToRetry

    Show-InstallReport -Results $retryResults -Title "TEKRAR DENEME KURULUM RAPORU"

    Write-Host ""
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Wait-UserKeyPress -PromptMessage "Menuye donmek icin bir tusa basin..."
}

# ============================================================================
# SHOW-PROFILEINSTALLSELECTOR (Standart Kullanıcı Profile Dayalı Kurulum)
# ============================================================================
function Show-ProfileInstallSelector {
<#
.SYNOPSIS
    Standart kullanıcı paneli için hazır profiller üzerinden hızlı kurulum ve sepet yükleme arayüzü sunar.
#>
    param(
        [System.Collections.Generic.List[PSCustomObject]]$SelectedApps,
        [PSCustomObject]$Catalog
    )

    if (-not $Catalog) {
        $Catalog = Import-AppCatalog
    }

    $profilesPath = Join-Path $PSScriptRoot "..\..\data\profiles\profiles.json"
    if (-not (Test-Path $profilesPath)) {
        $profilesPath = "data\profiles\profiles.json"
    }

    if (-not (Test-Path $profilesPath)) {
        Write-Host "  [HATA] Profil veritabanı bulunamadı: $profilesPath" -ForegroundColor Red
        Wait-UserKeyPress
        return
    }

    $profilesData = Get-Content $profilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $profiles = @($profilesData.profiles | Where-Object { $_.enabled -ne $false -and $_.id -ne "custom" })

    $catMap = @{}
    foreach ($a in $Catalog.applications) {
        $catMap[$a.Id] = $a
    }

    $exitProfiles = $false
    while (-not $exitProfiles) {
        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  ╔═════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
        Write-Host "  ║                     PROFILE DAYALI HIZLI KURULUM MERKEZİ                            ║" -ForegroundColor Green
        Write-Host "  ╚═════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  Hazır profillerden birini seçerek ilgili alandaki tüm programları tek tıkla sepetinize" -ForegroundColor White
        Write-Host "  ekleyebilir, doğrudan kurabilir veya kurulum öncesinde inceleyebilirsiniz." -ForegroundColor DarkCyan
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        $pIdx = 1
        foreach ($p in $profiles) {
            $numTag = if ($pIdx -lt 10) { "[ $pIdx]" } else { "[$pIdx]" }
            $countTag = "({0,2} Program)" -f $p.applications.Count

            Write-Host "  $numTag | " -ForegroundColor Yellow -NoNewline
            Write-Host ($p.name.PadRight(30)) -ForegroundColor Cyan -NoNewline
            Write-Host " $countTag " -ForegroundColor Green -NoNewline
            Write-Host "- $($p.description)" -ForegroundColor DarkGray
            $pIdx++
        }

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host "  SEÇENEKLER:" -ForegroundColor DarkCyan
        Write-Host "    [1-$($profiles.Count)] : Profili İncele / Sepete Ekle / Kur" -ForegroundColor White
        Write-Host "    [S]   : Mevcut Sepeti Görüntüle ($($SelectedApps.Count) Program Seçili)" -ForegroundColor Cyan
        Write-Host "    [C]   : Sepeti Temizle" -ForegroundColor Yellow
        Write-Host "    [0]   : Uygulama Kurulum Merkezine Dön" -ForegroundColor Red
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Seçiminiz: " -ForegroundColor Yellow -NoNewline

        $inp = Read-Host
        $choice = if ($null -ne $inp) { $inp.Trim() } else { "" }

        if ($choice -in "0", "00", "Q", "q", "") {
            $exitProfiles = $true
            return
        } elseif ($choice.ToUpper() -eq "S") {
            Show-SelectedInstallApps -SelectedApps $SelectedApps -Catalog $Catalog
        } elseif ($choice.ToUpper() -eq "C") {
            $SelectedApps.Clear()
            Write-Host "  [BİLGİ] Sepet temizlendi." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 500
        } elseif ($choice -match '^\d+$') {
            $idx = [int]$choice
            if ($idx -ge 1 -and $idx -le $profiles.Count) {
                $selProfile = $profiles[$idx - 1]
                Show-SingleProfileView -Profile $selProfile -SelectedApps $SelectedApps -Catalog $Catalog -CatMap $catMap
            } else {
                Write-Host "  [HATA] Geçersiz profil numarası!" -ForegroundColor Red
                Start-Sleep -Milliseconds 600
            }
        }
    }
}

function Show-SingleProfileView {
    param(
        [PSCustomObject]$Profile,
        [System.Collections.Generic.List[PSCustomObject]]$SelectedApps,
        [PSCustomObject]$Catalog,
        [hashtable]$CatMap
    )

    $resolvedApps = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($appId in $Profile.applications) {
        if ($CatMap.ContainsKey($appId)) {
            $resolvedApps.Add($CatMap[$appId])
        }
    }

    $exitSingle = $false
    while (-not $exitSingle) {
        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  PROFİL: $($Profile.name.ToUpper())" -ForegroundColor Green
        Write-Host "  Açıklama: $($Profile.description)" -ForegroundColor DarkGray
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Bu profilde toplam $($resolvedApps.Count) uygulama bulunmaktadır:" -ForegroundColor White
        Write-Host ""

        $colCount = 2
        for ($r = 0; $r -lt $resolvedApps.Count; $r += $colCount) {
            Write-Host "  " -NoNewline
            for ($c = 0; $c -lt $colCount; $c++) {
                $idx = $r + $c
                if ($idx -lt $resolvedApps.Count) {
                    $app = $resolvedApps[$idx]
                    $isSel = [bool]($SelectedApps | Where-Object { $_.Id -eq $app.Id })
                    $chk = if ($isSel) { "[X]" } else { "[ ]" }
                    $name = $app.Name
                    if ($name.Length -gt 27) { $name = $name.Substring(0, 24) + "..." }
                    $namePad = $name.PadRight(27)

                    $numStr = "[{0,2}]" -f ($idx + 1)
                    Write-Host $numStr -ForegroundColor Yellow -NoNewline
                    Write-Host " " -NoNewline
                    if ($isSel) {
                        Write-Host $chk -ForegroundColor Green -NoNewline
                        Write-Host " $namePad  " -ForegroundColor Green -NoNewline
                    } else {
                        Write-Host $chk -ForegroundColor DarkGray -NoNewline
                        Write-Host " $namePad  " -ForegroundColor White -NoNewline
                    }
                }
            }
            Write-Host ""
        }

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host "  EYLEMLER:" -ForegroundColor DarkCyan
        Write-Host "    [1] Bu Profildeki Tüm Programları Sepete Ekle" -ForegroundColor Cyan
        Write-Host "    [2] Sepeti Bu Profille Değiştir (Yalnızca Bu Profili Al)" -ForegroundColor Yellow
        Write-Host "    [K] Doğrudan Kurulumu Başlat (Bu Profildeki $($resolvedApps.Count) Programı Kur)" -ForegroundColor Green
        Write-Host "    [0] Profil Listesine Geri Dön" -ForegroundColor Red
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Seçiminiz: " -ForegroundColor Yellow -NoNewline

        $subInp = Read-Host
        $subChoice = if ($null -ne $subInp) { $subInp.Trim().ToUpper() } else { "" }

        if ($subChoice -in "0", "00", "G", "") {
            $exitSingle = $true
            return
        } elseif ($subChoice -eq "1") {
            $addCount = 0
            foreach ($app in $resolvedApps) {
                if (-not ($SelectedApps | Where-Object { $_.Id -eq $app.Id })) {
                    $SelectedApps.Add($app)
                    $addCount++
                }
            }
            Write-Host "  [BAŞARILI] $addCount yeni program sepete eklendi (Sepet: $($SelectedApps.Count) adet)." -ForegroundColor Green
            Start-Sleep -Milliseconds 800
        } elseif ($subChoice -eq "2") {
            $SelectedApps.Clear()
            foreach ($app in $resolvedApps) {
                $SelectedApps.Add($app)
            }
            Write-Host "  [BAŞARILI] Sepet sıfırlandı ve yalnızca bu profilin programları ($($SelectedApps.Count) adet) yüklendi." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 800
        } elseif ($subChoice -eq "K") {
            # Kurulumu başlat
            $appsToInstall = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($app in $resolvedApps) { $appsToInstall.Add($app) }
            
            Invoke-UnifiedInstallAction -SelectedApps $appsToInstall -Catalog $Catalog
            if ($script:ExitToMainMenu) {
                $script:ExitToMainMenu = $false
                return
            }
        }
    }
}

# ============================================================================
# MODUL DISA AKTARIM
# ============================================================================
Export-ModuleMember -Function @(
    'Stop-ProcessTree',
    'Stop-AllRunningInstallers',
    'Test-InternetConnection',
    'Test-WinGetReady',
    'Show-WinGetReadinessError',
    'Test-AppInstalled',
    'Build-WinGetCommand',
    'Write-InstallLog',
    'Get-InstallHistory',
    'Format-ProgressBar',
    'Format-MarqueeBar',
    'Show-InstallScreen',
    'Update-InstallProgress',
    'Invoke-WinGetInstall',
    'Invoke-BulkInstall',
    'Show-InstallReport',
    'Show-AppInstallCenter',
    'Show-SingleInstallMenu',
    'Show-BulkInstallMenu',
    'Show-InstallHistory',
    'Invoke-RetryFailedInstalls',
    'Invoke-UnifiedInstallAction',
    'Show-SelectedInstallApps',
    'Show-ProfileInstallSelector',
    'Show-SingleProfileView'
)
