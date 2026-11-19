<#
.SYNOPSIS
    AAU Kurulum Asistani - Program Yonetim ve Kaldirma Modulu
.DESCRIPTION
    Kurulu programlari Windows Kayit Defteri (HKLM 64-bit, HKLM 32-bit WOW6432Node, HKCU)
    ve WinGet listesi uzerinden gercek zamanli tespit eder.
    WinGet, MSI ve guvenli ayristirilmis yerel uninstaller (EXE) mekanizmalariyla
    tekli ve toplu kaldirma, durum dogrulama ve loglama islemlerini yurutur.
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

$script:CachedInstalledPrograms = $null
$script:CachedWinGetMap         = $null

# ============================================================================
# YARDIMCI: SPLIT-UNINSTALLCOMMANDLINE (Guvenli Komut Ayristirma - No Invoke-Expression)
# ============================================================================
function Split-UninstallCommandLine {
<#
.SYNOPSIS
    UninstallString veya QuietUninstallString parametresini guvenle ayristirir.
    Invoke-Expression kullanmaz, tirnak ve bosluklari dogru yonetir.
#>
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $cmd = $CommandLine.Trim()

    # 1. Tirnak icindeki calistirilabilir dosya: "C:\Program Files\App\unins000.exe" /SILENT
    if ($cmd -match '^"([^"]+)"\s*(.*)$') {
        return @{
            ExePath   = $matches[1].Trim()
            Arguments = $matches[2].Trim()
        }
    }

    # 2. Dogrudan var olan bir dosya ise
    if (Test-Path -LiteralPath $cmd -PathType Leaf -ErrorAction SilentlyContinue) {
        return @{
            ExePath   = $cmd
            Arguments = ""
        }
    }

    # 3. Surucu harfi ve .exe ile baslayan kalip
    if ($cmd -match '^([A-Za-z]:\\[^\s]+\.exe)\s*(.*)$') {
        return @{
            ExePath   = $matches[1].Trim()
            Arguments = $matches[2].Trim()
        }
    }

    # 4. Bosluklarla ayrilmis tokenlari sondan basa dogru dosya varligi kontrolu
    $tokens = $cmd -split '\s+'
    for ($i = $tokens.Count; $i -ge 1; $i--) {
        $candidate = ($tokens[0..($i - 1)] -join " ").Trim().Trim('"')
        if (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue) {
            $remArgs = if ($i -lt $tokens.Count) { ($tokens[$i..($tokens.Count - 1)] -join " ") } else { "" }
            return @{
                ExePath   = $candidate
                Arguments = $remArgs.Trim()
            }
        }
    }

    # 5. Varsayilan ayirma
    return @{
        ExePath   = $tokens[0].Trim().Trim('"')
        Arguments = if ($tokens.Count -gt 1) { ($tokens[1..($tokens.Count - 1)] -join " ").Trim() } else { "" }
    }
}

# ============================================================================
# GET-INSTALLEDPROGRAMS (Kayit Defteri + WinGet Birlestirilmis Envanter)
# ============================================================================
function Get-InstalledPrograms {
<#
.SYNOPSIS
    64-bit, 32-bit ve Kullanici Kayit Defteri alanlarindan ve WinGet paketlerinden
    kurulu gercek program listesini derler, WinGet paketleriyle eslestirir.
.OUTPUTS
    [PSCustomObject[]]
#>
    param(
        [switch]$IncludeSystemComponents,
        [switch]$RefreshCache
    )

    if (-not $RefreshCache -and $script:CachedInstalledPrograms -and $script:CachedInstalledPrograms.Count -gt 0) {
        return $script:CachedInstalledPrograms
    }

    # 1. WinGet Paket Haritasini Hazirla (Hizli arama tablosu)
    if ($RefreshCache -or -not $script:CachedWinGetMap) {
        $script:CachedWinGetMap = @{}
        $wingetExe = Get-Command "winget.exe" -ErrorAction SilentlyContinue
        if ($wingetExe) {
            try {
                $rawWinget = & winget.exe list --accept-source-agreements 2>&1
                foreach ($line in $rawWinget) {
                    if ($line -match '^(.{10,60})\s{2,}([A-Za-z0-9\.\-_]{3,60})\s{2,}([^\s]+)\s{2,}(.*)$') {
                        $wName = $matches[1].Trim().ToLower()
                        $wId   = $matches[2].Trim()
                        $wSrc  = $matches[4].Trim()
                        if ($wId -notmatch '^ARP\\' -and $wId -notmatch '^MSIX\\') {
                            $script:CachedWinGetMap[$wName] = @{ Id = $wId; Source = $wSrc }
                        }
                    }
                }
            } catch {}
        }
    }

    # 2. Katalog Dosyasindaki Bilinen Programlari Haritaya Ekle
    try {
        $root = if ($global:ProjectRoot) { $global:ProjectRoot }
                elseif ($script:ProjectRoot) { $script:ProjectRoot }
                else { (Get-Location).Path }
        $appsJsonPath = Join-Path $root "data\apps\apps.json"
        if (Test-Path $appsJsonPath) {
            $catJson = ConvertFrom-Json ([System.IO.File]::ReadAllText($appsJsonPath, [System.Text.Encoding]::UTF8))
            if ($catJson -and $catJson.applications) {
                foreach ($cApp in $catJson.applications) {
                    $cName = if ($cApp.Name) { $cApp.Name.Trim().ToLower() } else { "" }
                    $cId   = if ($cApp.Id) { $cApp.Id } elseif ($cApp.winget_id) { $cApp.winget_id } else { "" }
                    if ($cName -and $cId -and -not $script:CachedWinGetMap.ContainsKey($cName)) {
                        $script:CachedWinGetMap[$cName] = @{ Id = $cId; Source = "winget" }
                    }
                }
            }
        }
    } catch {}

    # 3. Kayit Defteri Yollari
    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $rawList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($path in $regPaths) {
        try {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $name = $item.DisplayName
                if (-not $name -or [string]::IsNullOrWhiteSpace($name)) { continue }
                $name = $name.Trim()

                # Sistem bilesenleri, guncellemeler ve kaldirilamaz kayitlari filtrele
                if (-not $IncludeSystemComponents) {
                    if ($item.SystemComponent -eq 1) { continue }
                    if ($item.ParentKeyName) { continue }
                    if ($item.NoRemove -eq 1 -and -not $item.UninstallString) { continue }
                    if ($name -match '^(KB\d+|Security Update|Update for|Hotfix)') { continue }
                }

                $version = if ($item.DisplayVersion) { "$($item.DisplayVersion)".Trim() } else { "" }
                $dedupKey = "$name|$version"
                if ($seen.Contains($dedupKey)) { continue }
                $null = $seen.Add($dedupKey)

                $publisher       = if ($item.Publisher) { "$($item.Publisher)".Trim() } else { "Bilinmiyor" }
                $installDate     = if ($item.InstallDate) { "$($item.InstallDate)".Trim() } else { "" }
                $installLocation = if ($item.InstallLocation) { "$($item.InstallLocation)".Trim() } else { "" }
                $uninstallString = if ($item.UninstallString) { "$($item.UninstallString)".Trim() } else { "" }
                $quietUninstall  = if ($item.QuietUninstallString) { "$($item.QuietUninstallString)".Trim() } else { "" }
                $isMsi           = ($item.WindowsInstaller -eq 1)
                $webUrl          = if ($item.URLInfoAbout) { "$($item.URLInfoAbout)".Trim() } elseif ($item.HelpLink) { "$($item.HelpLink)".Trim() } else { "" }
                $displayIcon     = if ($item.DisplayIcon) { "$($item.DisplayIcon)".Trim() } else { "" }

                # GUID Tespiti
                $guid = $null
                if ($item.PSChildName -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$') {
                    $guid = $item.PSChildName
                } elseif ($uninstallString -match '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}') {
                    $guid = $matches[0]
                }

                # WinGet Eslestirmesi
                $nameLower = $name.ToLower()
                $wingetId = $null
                $wingetSrc = "winget"
                if ($script:CachedWinGetMap.ContainsKey($nameLower)) {
                    $wingetId  = $script:CachedWinGetMap[$nameLower].Id
                    $wingetSrc = $script:CachedWinGetMap[$nameLower].Source
                } else {
                    # Kismen eslestirme
                    foreach ($k in $script:CachedWinGetMap.Keys) {
                        if ($k.Length -ge 5 -and ($nameLower.Contains($k) -or $k.Contains($nameLower))) {
                            $wingetId  = $script:CachedWinGetMap[$k].Id
                            $wingetSrc = $script:CachedWinGetMap[$k].Source
                            break
                        }
                    }
                }

                $isWinGetManaged = ($null -ne $wingetId -and $wingetId.Length -gt 0)

                # Kaldirma Yontemini Belirle
                $method = "Bilinmiyor"
                if ($isWinGetManaged) {
                    $method = "WinGet"
                } elseif ($isMsi -or $guid) {
                    $method = "MSI"
                } elseif ($quietUninstall -or $uninstallString) {
                    $method = "Yerel Uninstaller (EXE)"
                }

                # Boyut hesaplama (EstimatedSize KB cinsindedir)
                $sizeKB = 0
                if ($item.EstimatedSize) {
                    try { $sizeKB = [int64]$item.EstimatedSize } catch {}
                }
                $sizeMB = [Math]::Round($sizeKB / 1024, 1)

                $rawList.Add([PSCustomObject]@{
                    Name             = $name
                    Version          = if ($version) { $version } else { "Bilinmiyor" }
                    Publisher        = $publisher
                    InstallDate      = $installDate
                    InstallLocation  = $installLocation
                    SizeKB           = $sizeKB
                    SizeMB           = $sizeMB
                    UninstallString  = $uninstallString
                    QuietUninstall   = $quietUninstall
                    IsMsi            = $isMsi
                    Guid             = $guid
                    WebUrl           = $webUrl
                    DisplayIcon      = $displayIcon
                    RegistryKey      = $item.PSChildName
                    Architecture     = if ($path -match "Wow6432Node") { "32-bit" } else { "64-bit" }
                    Scope            = if ($path -match "HKCU") { "Kullanici" } else { "Makine" }
                    WinGetId         = $wingetId
                    WinGetSource     = $wingetSrc
                    IsWinGetManaged  = $isWinGetManaged
                    UninstallMethod  = $method
                })
            }
        } catch {}
    }

    $script:CachedInstalledPrograms = @($rawList | Sort-Object Name)
    return $script:CachedInstalledPrograms
}

# ============================================================================
# SEARCH-INSTALLEDPROGRAMS
# ============================================================================
function Search-InstalledPrograms {
<#
.SYNOPSIS
    Kurulu programlar arasinda isim, yayinci veya surume gore filtreleme yapar.
#>
    param(
        [Alias("SearchTerm", "Term", "Name")]
        [string]$Query = ""
    )

    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }

    $all = Get-InstalledPrograms
    if (-not $all) { return @() }

    $q = $Query.Trim()
    return @($all | Where-Object {
        $_.Name -like "*$q*" -or
        $_.Publisher -like "*$q*" -or
        $_.Version -like "*$q*" -or
        ($_.WinGetId -and $_.WinGetId -like "*$q*")
    } | Sort-Object Name)
}

# ============================================================================
# INVOKE-UNINSTALLSINGLEAPP (Gercek Program Kaldirma Islemi)
# ============================================================================
function Invoke-UninstallSingleApp {
<#
.SYNOPSIS
    Programi WinGet, MSI veya guvenle ayristirilmis yerel uninstaller uzerinden kaldirir.
    Sonuclari dogrular ve loglar.
.OUTPUTS
    [hashtable]
#>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("Program", "Application")]
        [PSCustomObject]$App,
        [switch]$NonInteractive,
        [switch]$NoWaitPrompt
    )

    $startTime = Get-Date
    $dispName = $App.Name
    $dispVer  = $App.Version

    # Kaldirma Onay Ekrani (Eger NonInteractive degilse)
    if (-not $NonInteractive) {
        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  PROGRAM KALDIRMA ONAYI" -ForegroundColor Red
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  [DIKKAT] Asagidaki program sistemden kaldirilacaktir:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    Program Adi        : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$dispName" -ForegroundColor White
        Write-Host "    Surum              : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$dispVer" -ForegroundColor White
        Write-Host "    Yayinci            : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($App.Publisher)" -ForegroundColor White
        Write-Host "    Kaldirma Yontemi   : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($App.UninstallMethod)" -ForegroundColor Green
        if ($App.WinGetId) {
            Write-Host "    WinGet Paket ID    : " -ForegroundColor DarkCyan -NoNewline
            Write-Host "$($App.WinGetId)" -ForegroundColor Cyan
        }
        if ($App.InstallLocation) {
            Write-Host "    Kurulum Konumu     : " -ForegroundColor DarkCyan -NoNewline
            Write-Host "$($App.InstallLocation)" -ForegroundColor DarkCyan
        }
        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Bu programi kaldirmak istediginize KESINLIKLE EMIN MISINIZ? (E/H) [Varsayilan: H]: " -ForegroundColor Red -NoNewline
        $conf = Read-Host
        if (-not $conf -or $conf.Trim().ToUpper() -ne "E") {
            Write-Host ""
            Write-Host "  [BILGI] Kaldirma islemi kullanici tarafindan iptal edildi." -ForegroundColor DarkCyan
            Start-Sleep -Seconds 1
            return @{ Success = $false; Cancelled = $true; Message = "Kullanici tarafindan iptal edildi." }
        }
    }

    Write-Host ""
    Write-Host "  '$dispName' kaldiriliyor, lutfen bekleyin..." -ForegroundColor Yellow
    Write-LogInfo "Program kaldirma baslatildi: $dispName ($($App.UninstallMethod))"

    $success = $false
    $methodUsed = ""
    $exitCode = -1
    $errorMsg = ""

    # ------------------------------------------------------------------------
    # YONTEM 1: WinGet ile Kaldirma (Oncelikli)
    # ------------------------------------------------------------------------
    if ($App.IsWinGetManaged -and $App.WinGetId) {
        $wingetExe = Get-Command "winget.exe" -ErrorAction SilentlyContinue
        if ($wingetExe) {
            Write-Host "  [WINGET] WinGet uzerinden kaldiriliyor (ID: $($App.WinGetId))..." -ForegroundColor DarkCyan
            $wArgs = @(
                'uninstall',
                '--id', $App.WinGetId,
                '--exact',
                '--accept-source-agreements',
                '--disable-interactivity'
            )
            if ($App.WinGetSource -and $App.WinGetSource -eq 'winget') {
                $wArgs += @('--source', 'winget')
            }

            try {
                $p = Start-Process -FilePath "winget.exe" -ArgumentList $wArgs -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
                if ($p) {
                    $exitCode = $p.ExitCode
                    if ($exitCode -eq 0) {
                        $success = $true
                        $methodUsed = "WinGet ($($App.WinGetId))"
                    } elseif ($exitCode -eq -1978335189) {
                        Write-Host "  [UYARI] Yonetici izni gerekiyor, UAC ile deneniyor..." -ForegroundColor Yellow
                        $pElev = Start-Process -FilePath "winget.exe" -ArgumentList $wArgs -Verb RunAs -Wait -PassThru -ErrorAction SilentlyContinue
                        if ($pElev -and $pElev.ExitCode -eq 0) {
                            $success = $true
                            $methodUsed = "WinGet (Elevated)"
                        }
                    }
                }
            } catch {
                Write-LogWarn "WinGet kaldirma hatasi: $($_.Exception.Message)"
            }
        }
    }

    # ------------------------------------------------------------------------
    # YONTEM 2: MSI (Windows Installer) ile Kaldirma
    # ------------------------------------------------------------------------
    if (-not $success -and ($App.IsMsi -or $App.Guid)) {
        $targetGuid = $App.Guid
        if (-not $targetGuid -and $App.RegistryKey -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$') {
            $targetGuid = $App.RegistryKey
        }

        if ($targetGuid -and $targetGuid -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$') {
            Write-Host "  [MSI] Windows Installer ile kaldiriliyor (GUID: $targetGuid)..." -ForegroundColor DarkCyan
            $msiArgs = "/x `"$targetGuid`" /norestart"

            try {
                $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -Verb RunAs -ErrorAction SilentlyContinue
                if (-not $p) {
                    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -ErrorAction SilentlyContinue
                }
                if ($p) {
                    $exitCode = $p.ExitCode
                    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
                        $success = $true
                        $methodUsed = "MSI ($targetGuid)"
                    }
                }
            } catch {
                Write-LogWarn "MSI kaldirma calistirma hatasi: $($_.Exception.Message)"
            }
        }
    }

    # ------------------------------------------------------------------------
    # YONTEM 3: Yerel Uninstaller (QuietUninstallString veya UninstallString)
    # ------------------------------------------------------------------------
    if (-not $success) {
        $rawCmd = if ($App.QuietUninstall) { $App.QuietUninstall.Trim() }
                  elseif ($App.UninstallString) { $App.UninstallString.Trim() }
                  else { "" }

        if ($rawCmd) {
            # Guvenli ayristirma (No Invoke-Expression!)
            $parsed = Split-UninstallCommandLine -CommandLine $rawCmd

            if ($parsed -and $parsed.ExePath) {
                Write-Host "  [YEREL] Kaldirici calistiriliyor: $($parsed.ExePath)..." -ForegroundColor DarkCyan
                if (Test-Path -LiteralPath $parsed.ExePath -ErrorAction SilentlyContinue) {
                    try {
                        $startParams = @{
                            FilePath    = $parsed.ExePath
                            Wait        = $true
                            PassThru    = $true
                            ErrorAction = 'SilentlyContinue'
                        }
                        if ($parsed.Arguments) { $startParams['ArgumentList'] = $parsed.Arguments }

                        # Gerekliyse RunAs ile calistir
                        $p = Start-Process @startParams -Verb RunAs
                        if (-not $p) { $p = Start-Process @startParams }

                        if ($p) {
                            $exitCode = $p.ExitCode
                            # Bircok uninstaller 0 veya 3010 doner
                            if ($exitCode -eq 0 -or $exitCode -eq 3010) {
                                $success = $true
                                $methodUsed = "Yerel Uninstaller ($($parsed.ExePath))"
                            }
                        }
                    } catch {
                        Write-LogWarn "Yerel uninstaller hatasi: $($_.Exception.Message)"
                        $errorMsg = $_.Exception.Message
                    }
                } else {
                    Write-LogError "Kaldirici dosya diskte bulunamadi: $($parsed.ExePath)"
                    $errorMsg = "Kaldirici dosya bulunamadi: $($parsed.ExePath)"
                }
            }
        }
    }

    # ------------------------------------------------------------------------
    # YONTEM 4: AppX / Modern Windows Paketi Kontrolu
    # ------------------------------------------------------------------------
    if (-not $success) {
        try {
            $shortName = ($dispName -split '\s+')[0]
            $appx = Get-AppxPackage -Name "*$shortName*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($appx) {
                Write-Host "  [APPX] Modern paket kaldiriliyor: $($appx.PackageFullName)..." -ForegroundColor DarkCyan
                Remove-AppxPackage -Package $appx.PackageFullName -ErrorAction Stop
                $success = $true
                $methodUsed = "AppX ($($appx.Name))"
            }
        } catch {}
    }

    # ------------------------------------------------------------------------
    # ASAMA 4: KALDIRMA SONRASI DOGRULAMA
    # ------------------------------------------------------------------------
    if (-not $methodUsed) {
        Write-Host ""
        Write-Host "  " + ("=" * 56) -ForegroundColor DarkCyan
        Write-Host "  KALDIRMA SONUCU" -ForegroundColor White
        Write-Host "  " + ("-" * 56) -ForegroundColor DarkCyan
        Write-Host "  Program: " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$dispName" -ForegroundColor White
        Write-Host ""
        Write-Host "  [X] Kaldirma islemi baslatilamadi!" -ForegroundColor Red
        if ($errorMsg) {
            Write-Host "      Hata: $errorMsg" -ForegroundColor Yellow
        } else {
            Write-Host "      Hata: Program icin gecerli bir kaldirici bulunamadi veya dosya eksik." -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  Durum: Basarisiz" -ForegroundColor Red
        Write-Host "  " + ("=" * 56) -ForegroundColor DarkCyan
        Write-LogError "$dispName kaldirilamadi: $errorMsg"

        if (-not $NoWaitPrompt -and -not $NonInteractive) {
            Write-Host ""
            Wait-UserKeyPress -PromptMessage "Menuye donmek icin bir tusa basin..."
        }

        return @{
            Success       = $false
            RecordRemoved = $false
            Method        = ""
            ExitCode      = -1
            Duration      = [int]((Get-Date) - $startTime).TotalSeconds
            ErrorMessage  = $errorMsg
        }
    }

    Start-Sleep -Seconds 1
    $script:CachedInstalledPrograms = $null

    # Kayit defterinde halen var mi kontrol et
    $stillInRegistry = @(Get-InstalledPrograms -RefreshCache | Where-Object {
        $_.Name -eq $dispName -or ($App.Guid -and $_.Guid -eq $App.Guid)
    })
    $recordRemoved = ($stillInRegistry.Count -eq 0)

    # Sonuc Ekrani
    Write-Host ""
    Write-Host "  " + ("=" * 56) -ForegroundColor DarkCyan
    Write-Host "  KALDIRMA SONUCU" -ForegroundColor White
    Write-Host "  " + ("-" * 56) -ForegroundColor DarkCyan
    Write-Host "  Program: " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$dispName" -ForegroundColor White
    Write-Host ""

    Write-Host "  [✓] Kaldirma islemi baslatildi." -ForegroundColor Green
    Write-Host "  [✓] Kaldirma islemi tamamlandi. (Yontem: $methodUsed | Kod: $exitCode)" -ForegroundColor Green

    $duration = [int]((Get-Date) - $startTime).TotalSeconds

    if ($recordRemoved) {
        Write-Host "  [✓] Program kaydi artik bulunmuyor." -ForegroundColor Green
        Write-Host ""
        Write-Host "  Durum: Basariyla kaldirildi." -ForegroundColor Green
        Write-LogSuccess "$dispName basariyla kaldirildi (Sure: ${duration}s, Yontem: $methodUsed)"
        $success = $true
    } else {
        Write-Host "  [!] Kaldirma komutu tamamlandi ancak program kaydi hâlâ mevcut." -ForegroundColor Yellow
        Write-Host "      (Program kaldiricisi yeniden baslatma gerektiriyor veya kullanici tarafindan tamamlanmamis olabilir)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Durum: Kaldirici calistirildi (Dogrulama bekleniyor)." -ForegroundColor Yellow
        Write-LogWarn "$dispName kaldirici calistirildi ancak kayit defterinde halen gorunuyor."
    }
    Write-Host "  " + ("=" * 56) -ForegroundColor DarkCyan

    if (-not $NoWaitPrompt -and -not $NonInteractive) {
        Write-Host ""
        Wait-UserKeyPress -PromptMessage "Menuye donmek icin bir tusa basin..."
    }

    return @{
        Success       = $success
        RecordRemoved = $recordRemoved
        Method        = $methodUsed
        ExitCode      = $exitCode
        Duration      = $duration
        ErrorMessage  = $errorMsg
    }
}

# ============================================================================
# SHOW-UNINSTALLMENU (Tekli Program Kaldirma Arayuzu)
# ============================================================================
function Show-UninstallMenu {
<#
.SYNOPSIS
    Program arama, secme ve guvenli tekli kaldirma ekranidir.
#>
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  Program Kaldirma (Tekli)" -ForegroundColor Red
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  Kaldirilacak programi bulmak icin arama terimi yazin (bos Enter ile iptal):" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Arama Terimi: " -ForegroundColor Yellow -NoNewline
    $query = Read-Host
    if ([string]::IsNullOrWhiteSpace($query)) { return }

    $matches = Search-InstalledPrograms -Query $query
    if ($matches.Count -eq 0) {
        Write-Host ""
        Write-Host "  [UYARI] '$query' ile eslesen kurulu program bulunamadi." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    Write-Host ""
    Write-Host "  ESLESEN PROGRAMLAR ('$query' - $($matches.Count) sonuc):" -ForegroundColor Green
    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan

    $idx = 1
    foreach ($m in $matches) {
        $numStr = "[$idx]".PadRight(4)
        $mName = if ($m.Name.Length -gt 32) { $m.Name.Substring(0, 29) + "..." } else { $m.Name }
        $mVer  = if ($m.Version.Length -gt 15) { $m.Version.Substring(0, 12) + "..." } else { $m.Version }
        $mMet  = "[$($m.UninstallMethod)]".PadRight(18)
        Write-Host "  $numStr $($mName.PadRight(33)) $($mVer.PadRight(16)) $mMet" -ForegroundColor White
        $idx++
    }

    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Kaldirilacak program numarasini secin [1-$($matches.Count) | 0=Iptal]: " -ForegroundColor Yellow -NoNewline
    $pick = Read-Host
    if (-not ($pick -match '^\d+$')) { return }
    $pNum = [int]$pick
    if ($pNum -lt 1 -or $pNum -gt $matches.Count) { return }

    $targetApp = $matches[$pNum - 1]
    $null = Invoke-UninstallSingleApp -App $targetApp
}

# ============================================================================
# SHOW-BULKUNINSTALLMENU (Toplu Program Kaldirma - Listeleme Sorunu Duzeltildi!)
# ============================================================================
function Show-BulkUninstallMenu {
<#
.SYNOPSIS
    Tum programlari ekranda aninda listeleyen, arama ve sayfalama destekli,
    coklu secim yapilabilen ve guvenli sirali kaldirma saglayan toplu kaldirma arayuzu.
#>
    $pageSize = 10
    $pageIndex = 0
    $searchTerm = ""
    $selectedApps = [System.Collections.Generic.List[PSCustomObject]]::new()

    $exitBulk = $false
    while (-not $exitBulk) {
        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  [ 2] | Program Yonetim Merkezi  >  TOPLU PROGRAM KALDIRMA" -ForegroundColor Red
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        $all = if ($searchTerm) { Search-InstalledPrograms -Query $searchTerm } else { Get-InstalledPrograms }
        $totalItems = $all.Count
        $totalPages = [Math]::Max(1, [int][Math]::Ceiling($totalItems / $pageSize))

        if ($pageIndex -ge $totalPages) { $pageIndex = $totalPages - 1 }
        if ($pageIndex -lt 0) { $pageIndex = 0 }

        $startIndex = $pageIndex * $pageSize
        $endIndex = [Math]::Min($startIndex + $pageSize - 1, $totalItems - 1)

        Write-Host "  KURULU PROGRAM LISTESI " -ForegroundColor Green -NoNewline
        Write-Host "(Sayfa $($pageIndex + 1)/$totalPages - Toplam $totalItems Program" -ForegroundColor DarkCyan -NoNewline
        if ($searchTerm) { Write-Host " - Filtre: '$searchTerm'" -ForegroundColor Yellow -NoNewline }
        Write-Host "):" -ForegroundColor DarkCyan
        Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan

        if ($totalItems -eq 0) {
            Write-Host "    [Eslesen veya kurulu program bulunamadi]" -ForegroundColor Red
        } else {
            for ($k = $startIndex; $k -le $endIndex; $k++) {
                $app = $all[$k]
                $localNum = ($k - $startIndex) + 1
                $isSelected = ($null -ne ($selectedApps | Where-Object { $_.Name -eq $app.Name }))
                $chk = if ($isSelected) { "[*]" } else { "[ ]" }
                $chkColor = if ($isSelected) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkGray }

                $pName = if ($app.Name.Length -gt 34) { $app.Name.Substring(0, 31) + "..." } else { $app.Name }
                $pVer  = if ($app.Version.Length -gt 14) { $app.Version.Substring(0, 11) + "..." } else { $app.Version }

                Write-Host "  $chk " -ForegroundColor $chkColor -NoNewline
                Write-Host "[$localNum] ".PadRight(5) -ForegroundColor Yellow -NoNewline
                Write-Host "$($pName.PadRight(35))" -ForegroundColor White -NoNewline
                Write-Host " $($pVer.PadRight(15))" -ForegroundColor DarkCyan -NoNewline
                Write-Host " $($app.UninstallMethod)" -ForegroundColor Green
            }
        }

        Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
        Write-Host ""

        # Secim Durumu
        Write-Host "  SEPET / SECILEN PROGRAMLAR (" -NoNewline
        Write-Host "$($selectedApps.Count) program secildi" -ForegroundColor Yellow -NoNewline
        Write-Host "):" -ForegroundColor White

        if ($selectedApps.Count -gt 0) {
            $sNames = @($selectedApps | ForEach-Object { $_.Name })
            if ($sNames.Count -le 5) {
                Write-Host "    Secilenler: $($sNames -join ', ')" -ForegroundColor Cyan
            } else {
                Write-Host "    Secilenler: $($sNames[0..3] -join ', ') ... ve $($sNames.Count - 4) program daha." -ForegroundColor Cyan
            }
        } else {
            Write-Host "    [Henuz program secilmedi. Numaralari girerek sepete ekleyin]" -ForegroundColor DarkGray
        }

        Write-Host ""
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host "  KOMUTLAR:" -ForegroundColor DarkCyan
        Write-Host "    [1-$([Math]::Max(1, ($endIndex - $startIndex + 1)))] : Bu sayfadaki programlari sec / cikar (Orn: 1,3 veya 1-4)" -ForegroundColor White
        Write-Host "    [N] Sonraki Sayfa      [P] Onceki Sayfa      [A] Ara / Filtrele" -ForegroundColor Cyan
        Write-Host "    [T] Bu Sayfayi Sec     [C] Sepeti Temizle    [F] Filtreyi Kaldir" -ForegroundColor Yellow
        Write-Host "    [K] KALDIRMAYI BASLAT  [0] Geri Don" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Seciminiz: " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host
        $choice = if ($null -ne $inp) { $inp.Trim() } else { "" }

        if ($choice -eq "0" -or $choice -eq "00") {
            $exitBulk = $true
            return
        } elseif ($choice.ToUpper() -eq "N") {
            if ($pageIndex -lt ($totalPages - 1)) { $pageIndex++ }
        } elseif ($choice.ToUpper() -eq "P") {
            if ($pageIndex -gt 0) { $pageIndex-- }
        } elseif ($choice.ToUpper() -eq "A") {
            Write-Host "  Arama terimi girin: " -ForegroundColor Yellow -NoNewline
            $st = Read-Host
            $searchTerm = if ($st) { $st.Trim() } else { "" }
            $pageIndex = 0
        } elseif ($choice.ToUpper() -eq "F") {
            $searchTerm = ""
            $pageIndex = 0
        } elseif ($choice.ToUpper() -eq "C") {
            $selectedApps.Clear()
            Write-Host "  [BILGI] Sepet temizlendi." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 400
        } elseif ($choice.ToUpper() -eq "T") {
            for ($k = $startIndex; $k -le $endIndex; $k++) {
                $cur = $all[$k]
                if (-not ($selectedApps | Where-Object { $_.Name -eq $cur.Name })) {
                    $selectedApps.Add($cur)
                }
            }
        } elseif ($choice.ToUpper() -eq "K") {
            if ($selectedApps.Count -eq 0) {
                Write-Host "  [UYARI] Kaldirilacak program secilmedi! Once program numaralarini secin." -ForegroundColor Red
                Start-Sleep -Seconds 1
                continue
            }

            # Toplu Kaldirma Onay Karti
            Show-ScreenTransition -Scrollable
            Show-AppHeader -Scrollable
            Write-Host ""
            Write-Host "  TOPLU KALDIRMA ONAYI" -ForegroundColor Red
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Write-Host ""
            Write-Host "  [DIKKAT] Asagidaki $($selectedApps.Count) program sirasiyla sistemden kaldirilacaktir:" -ForegroundColor Yellow
            Write-Host ""

            $uNum = 1
            foreach ($app in $selectedApps) {
                Write-Host "    $uNum. $($app.Name)".PadRight(35) -ForegroundColor White -NoNewline
                Write-Host " (Surum: $($app.Version))".PadRight(20) -ForegroundColor DarkCyan -NoNewline
                Write-Host " [Yontem: $($app.UninstallMethod)]" -ForegroundColor Green
                $uNum++
            }

            Write-Host ""
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Write-Host ""
            Write-Host "  Bu islemi baslatmak istediginize KESINLIKLE EMIN MISINIZ? (E/H) [Varsayilan: H]: " -ForegroundColor Red -NoNewline
            $confBulk = Read-Host
            if (-not $confBulk -or $confBulk.Trim().ToUpper() -ne "E") {
                Write-Host "  [BILGI] Toplu kaldirma iptal edildi." -ForegroundColor DarkCyan
                Start-Sleep -Seconds 1
                continue
            }

            # Sirali Kaldirma Islemi
            Write-Host ""
            $startTimeBulk = Get-Date
            $successCount = 0
            $failCount = 0
            $bulkResults = [System.Collections.Generic.List[PSCustomObject]]::new()

            $bIdx = 1
            foreach ($app in $selectedApps) {
                Write-Host "  [$bIdx/$($selectedApps.Count)] $($app.Name) kaldiriliyor..." -ForegroundColor Yellow
                $res = Invoke-UninstallSingleApp -App $app -NonInteractive -NoWaitPrompt

                $resObj = [PSCustomObject]@{
                    Name     = $app.Name
                    Success  = $res.Success
                    Method   = $res.Method
                    ExitCode = $res.ExitCode
                }
                $bulkResults.Add($resObj)

                if ($res.Success) {
                    $successCount++
                } else {
                    $failCount++
                }
                $bIdx++
                Start-Sleep -Milliseconds 500
            }

            # Sonuc Raporu
            $totalDuration = [int]((Get-Date) - $startTimeBulk).TotalSeconds
            Show-ScreenTransition -Scrollable
            Show-AppHeader -Scrollable
            Write-Host ""
            Write-Host "  TOPLU KALDIRMA RAPORU" -ForegroundColor Green
            Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
            Write-Host ""
            Write-Host "  Toplam Islem : $($selectedApps.Count) program | Sure: ${totalDuration}s" -ForegroundColor White
            Write-Host "  Basarili     : $successCount" -ForegroundColor Green
            Write-Host "  Basarisiz    : $failCount" -ForegroundColor Red
            Write-Host ""
            Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan

            foreach ($r in $bulkResults) {
                $statusTag = if ($r.Success) { "[✓ BASARILI]" } else { "[X BASARISIZ]" }
                $statusColor = if ($r.Success) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
                Write-Host "  $statusTag " -ForegroundColor $statusColor -NoNewline
                Write-Host "$($r.Name)".PadRight(35) -ForegroundColor White -NoNewline
                Write-Host " (Yontem: $($r.Method))" -ForegroundColor DarkCyan
            }

            Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
            Write-Host ""
            $selectedApps.Clear()
            $script:CachedInstalledPrograms = $null
            Wait-UserKeyPress -PromptMessage "Program Yonetim Merkezine donmek icin bir tusa basin..."
            return
        } else {
            # Numaralari ayristir (Orn: 1,3 veya 1-4)
            $tokens = $choice -split '[,;\s]+'
            foreach ($t in $tokens) {
                if ($t -match '^(\d+)-(\d+)$') {
                    $s = [int]$matches[1]; $e = [int]$matches[2]
                    if ($s -le $e) {
                        for ($x = $s; $x -le $e; $x++) {
                            $globalIdx = $startIndex + ($x - 1)
                            if ($globalIdx -ge 0 -and $globalIdx -lt $all.Count) {
                                $target = $all[$globalIdx]
                                $existing = $selectedApps | Where-Object { $_.Name -eq $target.Name }
                                if ($existing) { $selectedApps.Remove($existing) }
                                else { $selectedApps.Add($target) }
                            }
                        }
                    }
                } elseif ($t -match '^\d+$') {
                    $x = [int]$t
                    $globalIdx = $startIndex + ($x - 1)
                    if ($globalIdx -ge 0 -and $globalIdx -lt $all.Count) {
                        $target = $all[$globalIdx]
                        $existing = $selectedApps | Where-Object { $_.Name -eq $target.Name }
                        if ($existing) { $selectedApps.Remove($existing) }
                        else { $selectedApps.Add($target) }
                    }
                }
            }
        }
    }
}

# ============================================================================
# SHOW-PROGRAMMANAGEMENTCENTER (Tek Liste - Sayfasiz Tum Programlar)
# ============================================================================
function Show-ProgramManagementCenter {
<#
.SYNOPSIS
    Sistemdeki tum kurulu programlari tek bir kesintisiz listede sunan,
    sayfa degistirme karmaşasi olmadan tekli ve coklu kaldirma imkani veren
    merkezi program yonetim ekrani.
#>
    $searchFilter = ""

    $exitCenter = $false
    while (-not $exitCenter) {
        Show-ScreenTransition -Scrollable
        Show-AppHeader -Scrollable
        Write-Host ""
        Write-Host "  [ 2] | Program Yonetim ve Kaldirma Merkezi  >  TUM PROGRAMLAR" -ForegroundColor Green
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        $allPrograms = if ($searchFilter) { Search-InstalledPrograms -Query $searchFilter }
                       else { Get-InstalledPrograms }

        $totalProgs = $allPrograms.Count

        # Durum ve Ozet Bilgi Satiri
        Write-Host "  KURULU PROGRAM LISTESI " -ForegroundColor Green -NoNewline
        Write-Host "(Toplam $totalProgs Program" -ForegroundColor DarkCyan -NoNewline
        if ($searchFilter) {
            Write-Host " | Filtre: '$searchFilter' - Temizlemek icin [T]" -ForegroundColor Yellow -NoNewline
        }
        Write-Host "):" -ForegroundColor DarkCyan
        Write-Host ""

        # Tablo Basligi
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host "  NO     PROGRAM ADI                         SURUM           YONTEM / TUR" -ForegroundColor DarkCyan
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

        if ($totalProgs -eq 0) {
            Write-Host ""
            Write-Host "    [!] Eslesen veya sistemde kayitli program bulunamadi." -ForegroundColor Yellow
            Write-Host ""
        } else {
            for ($k = 0; $k -lt $totalProgs; $k++) {
                $prog = $allPrograms[$k]
                $localNum = $k + 1
                $numTag = if ($totalProgs -ge 100) { ("[{0:D3}]" -f $localNum).PadRight(6) } else { ("[{0:D2}]" -f $localNum).PadRight(6) }

                $pName = if ($prog.Name.Length -gt 35) { $prog.Name.Substring(0, 32) + "..." } else { $prog.Name }
                $pVer  = if ($prog.Version.Length -gt 15) { $prog.Version.Substring(0, 12) + "..." } else { $prog.Version }
                $pMethod = if ($prog.UninstallMethod) { "[$($prog.UninstallMethod)]" } else { "[Yerel]" }

                Write-Host "  " -NoNewline
                Write-Host "$numTag" -ForegroundColor Yellow -NoNewline
                Write-Host " $($pName.PadRight(36))" -ForegroundColor White -NoNewline
                Write-Host " $($pVer.PadRight(16))" -ForegroundColor DarkCyan -NoNewline
                Write-Host " $pMethod" -ForegroundColor Green
            }
        }

        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""

        # Son Derece Net ve Sade Komut Cubugu
        $maxLimitStr = if ($totalProgs -gt 0) { "1-$totalProgs" } else { "-" }
        Write-Host "  ISLEMLER:" -ForegroundColor DarkCyan
        Write-Host "    [$maxLimitStr] : Programi Kaldir (Tek secim: 1 | Coklu secim: 1,3 veya 1-4)" -ForegroundColor White
        Write-Host "    [A]      : Program Ara / Filtrele" -ForegroundColor Cyan
        Write-Host "    [T]      : Tum Programlari Goster (Filtreyi Temizle)" -ForegroundColor Cyan
        Write-Host "    [D]      : Program Detaylarini Gor" -ForegroundColor Yellow
        Write-Host "    [R]      : Listeyi Yenile" -ForegroundColor Yellow
        Write-Host "    [0]      : Ana Menuye Don" -ForegroundColor Red
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        Write-Host ""
        Write-Host "  Seciminiz: " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host
        $choice = if ($null -ne $inp) { $inp.Trim() } else { "" }

        if ($choice -eq "0" -or $choice -eq "00") {
            $exitCenter = $true
            return
        } elseif ($choice.ToUpper() -eq "A") {
            Write-Host ""
            Write-Host "  Aranacak program adi (bos Enter ile iptal): " -ForegroundColor Yellow -NoNewline
            $st = Read-Host
            if (-not [string]::IsNullOrWhiteSpace($st)) {
                $searchFilter = $st.Trim()
            }
        } elseif ($choice.ToUpper() -eq "T" -or $choice.ToUpper() -eq "C") {
            $searchFilter = ""
        } elseif ($choice.ToUpper() -eq "R") {
            Write-Host ""
            Write-Host "  [BILGI] Program listesi ve paketler yenileniyor..." -ForegroundColor Yellow
            $script:CachedInstalledPrograms = $null
            $script:CachedWinGetMap = $null
            $null = Get-InstalledPrograms -RefreshCache
            Write-Host "  [BASARILI] Liste guncellendi." -ForegroundColor Green
            Start-Sleep -Milliseconds 500
        } elseif ($choice.ToUpper() -eq "D") {
            Write-Host ""
            Write-Host "  Detayini incelemek istediginiz program numarasi [$maxLimitStr]: " -ForegroundColor Yellow -NoNewline
            $dPick = Read-Host
            if ($dPick -match '^\d+$') {
                $dNum = [int]$dPick
                if ($dNum -ge 1 -and $dNum -le $allPrograms.Count) {
                    Show-ProgramDetailCard -Program $allPrograms[$dNum - 1]
                }
            }
        } else {
            # Numaralari (Tekli veya Coklu Secim) Ayristir
            $tokens = $choice -split '[,;\s]+'
            $selectedTargets = [System.Collections.Generic.List[PSCustomObject]]::new()

            foreach ($t in $tokens) {
                if ($t -match '^(\d+)-(\d+)$') {
                    $s = [int]$matches[1]; $e = [int]$matches[2]
                    if ($s -le $e) {
                        for ($x = $s; $x -le $e; $x++) {
                            if ($x -ge 1 -and $x -le $allPrograms.Count) {
                                $item = $allPrograms[$x - 1]
                                if (-not ($selectedTargets | Where-Object { $_.Name -eq $item.Name })) {
                                    $selectedTargets.Add($item)
                                }
                            }
                        }
                    }
                } elseif ($t -match '^\d+$') {
                    $x = [int]$t
                    if ($x -ge 1 -and $x -le $allPrograms.Count) {
                        $item = $allPrograms[$x - 1]
                        if (-not ($selectedTargets | Where-Object { $_.Name -eq $item.Name })) {
                            $selectedTargets.Add($item)
                        }
                    }
                }
            }

            if ($selectedTargets.Count -eq 1) {
                # Tekli Kaldirma
                $null = Invoke-UninstallSingleApp -App $selectedTargets[0]
                $script:CachedInstalledPrograms = $null
            } elseif ($selectedTargets.Count -gt 1) {
                # Coklu Kaldirma Onay Ekrani
                Show-ScreenTransition -Scrollable
                Show-AppHeader -Scrollable
                Write-Host ""
                Write-Host "  TOPLU PROGRAM KALDIRMA ONAYI" -ForegroundColor Red
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Write-Host ""
                Write-Host "  Asagidaki $($selectedTargets.Count) program sirasiyla sistemden kaldirilacaktir:" -ForegroundColor Yellow
                Write-Host ""

                $kNum = 1
                foreach ($app in $selectedTargets) {
                    Write-Host "    $kNum. $($app.Name)".PadRight(38) -ForegroundColor White -NoNewline
                    Write-Host " (Surum: $($app.Version))".PadRight(20) -ForegroundColor DarkCyan -NoNewline
                    Write-Host " [$($app.UninstallMethod)]" -ForegroundColor Green
                    $kNum++
                }

                Write-Host ""
                Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
                Write-Host ""
                Write-Host "  Bu islemi baslatmak istediginize emin misiniz? (E/H) [Varsayilan: H]: " -ForegroundColor Red -NoNewline
                $conf = Read-Host
                if ($conf -and $conf.Trim().ToUpper() -eq "E") {
                    $sCount = 0; $fCount = 0
                    $uIdx = 1
                    foreach ($app in $selectedTargets) {
                        Write-Host ""
                        Write-Host "  [$uIdx/$($selectedTargets.Count)] $($app.Name) kaldiriliyor..." -ForegroundColor Yellow
                        $uRes = Invoke-UninstallSingleApp -App $app -NonInteractive -NoWaitPrompt
                        if ($uRes.Success) { $sCount++ } else { $fCount++ }
                        $uIdx++
                        Start-Sleep -Milliseconds 400
                    }
                    Write-Host ""
                    Write-Host "  [TAMAMLANDI] Toplu Kaldirma: $sCount Basarili, $fCount Basarisiz." -ForegroundColor Green
                    $script:CachedInstalledPrograms = $null
                    Start-Sleep -Seconds 1
                    Wait-UserKeyPress -PromptMessage "Devam etmek icin bir tusa basin..."
                }
            } else {
                Write-Host "  [HATA] Gecersiz giris veya numara." -ForegroundColor Red
                Start-Sleep -Milliseconds 800
            }
        }
    }
}

# ============================================================================
# DIGER YONETIM VE GUNCELLEME ISLEVLERI (Mevcut Fonksiyonlar Korunuyor)
# ============================================================================

function Get-WinGetUpgrades {
    $upgrades = [System.Collections.Generic.List[PSCustomObject]]::new()
    $wingetExe = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if (-not $wingetExe) { return @() }

    try {
        $rawOutput = & winget.exe upgrade --include-unknown 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $rawOutput) { return @() }

        $started = $false
        foreach ($line in $rawOutput) {
            $l = "$line".Trim()
            if (-not $l) { continue }
            if ($l -match '^-{5,}') { $started = $true; continue }
            if ($started) {
                if ($l -match '^\d+\s+upgrades?\s+available' -or $l -match '^\d+\s+guncelleme') { continue }
                $parts = $l -split '\s{2,}'
                if ($parts.Count -ge 4) {
                    $upgrades.Add([PSCustomObject]@{
                        Name             = $parts[0].Trim()
                        Id               = $parts[1].Trim()
                        InstalledVersion = $parts[2].Trim()
                        AvailableVersion = $parts[3].Trim()
                        Source           = if ($parts.Count -ge 5) { $parts[4].Trim() } else { "winget" }
                    })
                } elseif ($l -match '^(.*?)\s+([a-zA-Z0-9_\-\.]+)\s+(\S+)\s+(\S+)\s+(\S+)$') {
                    $upgrades.Add([PSCustomObject]@{
                        Name             = $matches[1].Trim()
                        Id               = $matches[2].Trim()
                        InstalledVersion = $matches[3].Trim()
                        AvailableVersion = $matches[4].Trim()
                        Source           = $matches[5].Trim()
                    })
                }
            }
        }
    } catch {
        Write-LogWarn "WinGet upgrade ayristirma hatasi: $($_.Exception.Message)"
    }
    return @($upgrades)
}

function Show-UpdateCheckMenu {
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  Guncelleme Denetimi" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  WinGet uzerinden guncellenebilir programlar taranıyor..." -ForegroundColor Yellow

    $upgrades = Get-WinGetUpgrades
    if ($upgrades.Count -eq 0) {
        Write-Host ""
        Write-Host "  [TEBRIKLER] Sistemdeki tum WinGet programlari guncel!" -ForegroundColor Green
        Write-Host ""
        Wait-UserKeyPress -PromptMessage "Menuye donmek icin bir tusa basin..."
        return
    }

    Write-Host ""
    Write-Host "  GUNCELLENEBILIR PROGRAMLAR ($($upgrades.Count) adet):" -ForegroundColor Green
    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan

    $idx = 1
    foreach ($u in $upgrades) {
        $numStr = "[$idx]".PadRight(4)
        $uName = if ($u.Name.Length -gt 32) { $u.Name.Substring(0, 29) + "..." } else { $u.Name }
        $uNamePadded = $uName.PadRight(33)
        $verDiff = "$($u.InstalledVersion) -> $($u.AvailableVersion)".PadRight(28)
        Write-Host "  $numStr $uNamePadded $verDiff $($u.Source)" -ForegroundColor White
        $idx++
    }

    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Tumunu guncellemek icin [T], tekli icin program numarasi [1-$($upgrades.Count)], iptal icin [0]: " -ForegroundColor Yellow -NoNewline
    $ans = Read-Host
    if ($ans.ToUpper() -eq "T") {
        Invoke-UpgradeAllPrograms
    } elseif ($ans -match '^\d+$') {
        $n = [int]$ans
        if ($n -ge 1 -and $n -le $upgrades.Count) {
            Invoke-UpgradeSingleProgram -TargetUpgrade $upgrades[$n - 1]
        }
    }
}

function Invoke-UpgradeAllPrograms {
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  TUM PROGRAMLARI GUNCELLE" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""

    Write-Host "  Tum programlari guncellemek istediginize emin misiniz? (E/H) [Varsayilan: E]: " -ForegroundColor Yellow -NoNewline
    $conf = Read-Host
    if ($conf -and $conf.Trim().ToUpper() -ne "E") { return }

    Write-Host ""
    Write-Host "  WinGet upgrade --all baslatiliyor..." -ForegroundColor Green
    Write-LogInfo "Tum programlarin guncellenmesi baslatildi."

    & winget.exe upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements
    Write-Host ""
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Wait-UserKeyPress -PromptMessage "Menuye donmek icin bir tusa basin..."
}

function Invoke-UpgradeSingleProgram {
    param([PSCustomObject]$TargetUpgrade)

    if (-not $TargetUpgrade) {
        $upgrades = Get-WinGetUpgrades
        if ($upgrades.Count -eq 0) {
            Write-Host "  Guncellenecek program bulunamadi." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            return
        }
        $TargetUpgrade = $upgrades[0]
    }

    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  TEKLI PROGRAM GUNCELLEME" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  Guncellenecek Program: $($TargetUpgrade.Name)" -ForegroundColor White
    Write-Host "  Surum: $($TargetUpgrade.InstalledVersion) -> $($TargetUpgrade.AvailableVersion)" -ForegroundColor Green
    Write-Host ""

    Write-Host "  Guncelleme baslatiliyor..." -ForegroundColor Yellow
    & winget.exe upgrade --id $TargetUpgrade.Id --exact --accept-source-agreements --accept-package-agreements
    Write-Host ""
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Wait-UserKeyPress -PromptMessage "Menuye donmek icin bir tusa basin..."
}

function Show-InstalledProgramsList {
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  Kurulu Programlar Listesi" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  Program listesi taranıyor, lutfen bekleyin..." -ForegroundColor Yellow

    $all = Get-InstalledPrograms -RefreshCache
    Clear-Host
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  Kurulu Programlar ($($all.Count) Adet)" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""

    Write-Host "  #     PROGRAM ADI                     SURUM          YAYINCI              BOYUT" -ForegroundColor DarkCyan
    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan

    $totalMB = 0
    $idx = 1
    foreach ($p in $all) {
        $nStr = "[$idx]".PadRight(5)
        $pName = if ($p.Name.Length -gt 30) { $p.Name.Substring(0, 27) + "..." } else { $p.Name }
        $pVer = if ($p.Version.Length -gt 13) { $p.Version.Substring(0, 10) + "..." } else { $p.Version }
        $pPub = if ($p.Publisher.Length -gt 20) { $p.Publisher.Substring(0, 17) + "..." } else { $p.Publisher }
        $sizeStr = if ($p.SizeMB -gt 0) { "$($p.SizeMB) MB".PadLeft(9) } else { "      -  " }
        $totalMB += $p.SizeMB
        Write-Host "  $nStr $($pName.PadRight(31)) $($pVer.PadRight(14)) $($pPub.PadRight(21)) $sizeStr" -ForegroundColor White
        $idx++
    }

    $totalGB = [Math]::Round($totalMB / 1024, 2)
    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
    Write-Host "  Toplam: $($all.Count) Program | Yaklasik Toplam Disk Alani: $totalGB GB" -ForegroundColor Green
    Write-Host ""
    Wait-UserKeyPress -PromptMessage "Menuye donmek icin bir tusa basin..."
}

function Show-ProgramSearch {
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  Kurulu Program Arama" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  Aranacak program adi, yayinci veya surum bilgisi girin:" -ForegroundColor DarkCyan
    Write-Host "  Arama Terimi: " -ForegroundColor Yellow -NoNewline
    $term = Read-Host
    if ([string]::IsNullOrWhiteSpace($term)) { return }

    $results = Search-InstalledPrograms -Query $term
    if ($results.Count -eq 0) {
        Write-Host ""
        Write-Host "  [UYARI] '$term' terimiyle eslesen program bulunamadi." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    Write-Host ""
    Write-Host "  ARAMA SONUCLARI ('$term' - $($results.Count) sonuc):" -ForegroundColor Green
    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan

    $idx = 1
    foreach ($r in $results) {
        $numStr = "[$idx]".PadRight(4)
        $rName = if ($r.Name.Length -gt 32) { $r.Name.Substring(0, 29) + "..." } else { $r.Name }
        $rVer = if ($r.Version.Length -gt 15) { $r.Version.Substring(0, 12) + "..." } else { $r.Version }
        Write-Host "  $numStr $($rName.PadRight(33)) $($rVer.PadRight(16)) $($r.Publisher)" -ForegroundColor White
        $idx++
    }

    Write-Host ("  " + ("-" * 82)) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Detay incelemek istediginiz program numarasi [1-$($results.Count) | 0=Geri]: " -ForegroundColor Yellow -NoNewline
    $pick = Read-Host
    if ($pick -match '^\d+$') {
        $pNum = [int]$pick
        if ($pNum -ge 1 -and $pNum -le $results.Count) {
            Show-ProgramDetailCard -Program $results[$pNum - 1]
        }
    }
}

function Show-ProgramDetailCard {
    param([PSCustomObject]$Program)

    if (-not $Program) { return }

    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  PROGRAM DETAY KARTI: $($Program.Name)" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""

    Write-Host "    Program Adi        : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.Name)" -ForegroundColor White
    Write-Host "    Surum              : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.Version)" -ForegroundColor Green
    Write-Host "    Yayinci            : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.Publisher)" -ForegroundColor White
    Write-Host "    Kaldirma Yontemi   : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.UninstallMethod)" -ForegroundColor Green
    if ($Program.WinGetId) {
        Write-Host "    WinGet Paket ID    : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($Program.WinGetId)" -ForegroundColor Cyan
    }
    Write-Host "    Kurulum Tarihi     : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.InstallDate)" -ForegroundColor White
    Write-Host "    Mimari / Kapsam    : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.Architecture) / $($Program.Scope)" -ForegroundColor White
    Write-Host "    Tahmini Boyut      : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.SizeMB) MB" -ForegroundColor White
    Write-Host "    Kurulum Konumu     : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.InstallLocation)" -ForegroundColor DarkCyan
    Write-Host "    Kaldirma Komutu    : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($Program.UninstallString)" -ForegroundColor DarkCyan

    Write-Host ""
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host "  ISLEMLER:" -ForegroundColor DarkCyan
    Write-Host "    [1] Bu Programi Kaldir (Uninstall)" -ForegroundColor Red
    if ($Program.InstallLocation -and (Test-Path $Program.InstallLocation)) {
        Write-Host "    [2] Kurulum Klasorunu Ac (Explorer)" -ForegroundColor Cyan
    }
    Write-Host "    [0] Geri Don" -ForegroundColor White
    Write-Host ""
    Write-Host "  Seciminiz: " -ForegroundColor Yellow -NoNewline
    $act = Read-Host

    if ($act -eq "1") {
        $null = Invoke-UninstallSingleApp -App $Program
    } elseif ($act -eq "2" -and $Program.InstallLocation) {
        Invoke-OpenInstallLocation -App $Program
    }
}

function Show-ProgramVersionInfo {
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  Program Surum Bilgisi" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  Surumunu ogrenmek istediginiz programin adini girin: " -ForegroundColor Yellow -NoNewline
    $q = Read-Host
    if ([string]::IsNullOrWhiteSpace($q)) { return }

    $res = Search-InstalledPrograms -Query $q
    if ($res.Count -eq 0) {
        Write-Host "  [UYARI] Program bulunamadi." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }
    Show-ProgramDetailCard -Program $res[0]
}

function Show-ProgramPublisherInfo {
    Show-ScreenTransition -Scrollable
    Show-AppHeader -Scrollable
    Write-Host ""
    Write-Host "  [ 2] | Program Yonetim Merkezi  >  Program Yayincisi Bilgisi" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""
    Write-Host "  Yayinci adini veya program adini girin: " -ForegroundColor Yellow -NoNewline
    $q = Read-Host
    if ([string]::IsNullOrWhiteSpace($q)) { return }

    $all = Get-InstalledPrograms
    $matched = @($all | Where-Object { $_.Publisher -like "*$q*" -or $_.Name -like "*$q*" })
    if ($matched.Count -eq 0) {
        Write-Host "  [UYARI] Yayinci veya program bulunamadi." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    $targetPub = $matched[0].Publisher
    $pubApps = @($all | Where-Object { $_.Publisher -eq $targetPub })
    Write-Host ""
    Write-Host "  Yayinci: $targetPub ($($pubApps.Count) Program)" -ForegroundColor Green
    foreach ($pa in $pubApps) {
        Write-Host "    - $($pa.Name) ($($pa.Version))" -ForegroundColor White
    }
    Write-Host ""
    Wait-UserKeyPress -PromptMessage "Menuye donmek icin bir tusa basin..."
}

function Invoke-OpenInstallLocation {
    param(
        [Alias("Program", "Application")]
        [PSCustomObject]$App
    )

    if (-not $App) {
        Write-Host "  Konumunu acmak istediginiz programin adini girin: " -ForegroundColor Yellow -NoNewline
        $q = Read-Host
        if ([string]::IsNullOrWhiteSpace($q)) { return }
        $res = Search-InstalledPrograms -Query $q
        if ($res.Count -eq 0) {
            Write-Host "  [UYARI] Program bulunamadi." -ForegroundColor Red
            Start-Sleep -Seconds 1
            return
        }
        $App = $res[0]
    }

    $targetPath = $App.InstallLocation
    if (-not $targetPath -or -not (Test-Path $targetPath)) {
        if ($App.UninstallString -match '^"?([^"]+\\[^\\]+\.[a-zA-Z0-9]+)"?') {
            $extracted = Split-Path $matches[1] -Parent
            if (Test-Path $extracted) { $targetPath = $extracted }
        }
    }

    if ($targetPath -and (Test-Path $targetPath)) {
        Start-Process "explorer.exe" -ArgumentList "`"$targetPath`""
        Write-Host "  [BASARILI] Klasor Explorer'da acildi: $targetPath" -ForegroundColor Green
        Start-Sleep -Seconds 1
    } else {
        Write-Host "  [UYARI] '$($App.Name)' icin gecerli bir kurulum klasoru tespit edilemedi." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

function Show-FilteredProgramsMenu {
    Show-ProgramManagementCenter
}

# ============================================================================
# MODUL DISA AKTARIM
# ============================================================================
Export-ModuleMember -Function @(
    'Get-InstalledPrograms',
    'Search-InstalledPrograms',
    'Split-UninstallCommandLine',
    'Get-WinGetUpgrades',
    'Show-UpdateCheckMenu',
    'Invoke-UpgradeAllPrograms',
    'Invoke-UpgradeSingleProgram',
    'Show-UninstallMenu',
    'Invoke-UninstallSingleApp',
    'Show-BulkUninstallMenu',
    'Show-ProgramManagementCenter',
    'Show-InstalledProgramsList',
    'Show-ProgramSearch',
    'Show-ProgramDetailCard',
    'Show-ProgramVersionInfo',
    'Show-ProgramPublisherInfo',
    'Invoke-OpenInstallLocation',
    'Show-FilteredProgramsMenu'
)
