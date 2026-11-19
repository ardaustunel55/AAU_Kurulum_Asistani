#Requires -Version 5.1
<#
.SYNOPSIS
    AAU Kurulum Asistani - Profil Yonetimi, Ayar Yonetimi ve Yedekleme Modulu
.DESCRIPTION
    Profil yonetimi (olustur, duzenle, sil, kopyala, program ekle/cikar),
    kurulum ayarlari yonetimi ve yedekleme/geri yukleme islemleri icin
    tam etkilesimli konsol menuleri saglar.
.NOTES
    Bagimlilık: admin_core.psm1
    PowerShell 5.1 uyumlu
#>

#region ─── YARDIMCI FONKSİYONLAR ─────────────────────────────────────────────

$adminCorePath = Join-Path $PSScriptRoot "admin_core.psm1"
if (Test-Path $adminCorePath) {
    Import-Module $adminCorePath -Global -ErrorAction SilentlyContinue
}

if (-not (Get-Command "Write-LogInfo" -ErrorAction SilentlyContinue)) {
    function Write-LogInfo    { param([string]$m) }
    function Write-LogWarn    { param([string]$m) }
    function Write-LogError   { param([string]$m) }
    function Write-LogSuccess { param([string]$m) }
}

function Get-ProjectRootDir {
    if ($global:ProjectRoot -and (Test-Path $global:ProjectRoot)) { return $global:ProjectRoot }
    if ($script:ProjectRoot -and (Test-Path $script:ProjectRoot)) { return $script:ProjectRoot }
    $candidate = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    return (Get-Location).Path
}

function Get-ProfilesFilePath {
    return Join-Path (Get-ProjectRootDir) "data\profiles\profiles.json"
}

function Get-AppsFilePath {
    return Join-Path (Get-ProjectRootDir) "data\apps\apps.json"
}

function Get-SettingsFilePath {
    return Join-Path (Get-ProjectRootDir) "config\settings.json"
}

function Get-BackupDirPath {
    return Join-Path (Get-ProjectRootDir) "data\backups"
}

function Read-ProfilesJson {
    $path = Get-ProfilesFilePath
    if (-not (Test-Path $path)) {
        return [PSCustomObject]@{
            version      = "1.0.0"
            last_updated = (Get-Date -Format "yyyy-MM-dd")
            profiles     = @()
        }
    }
    try {
        $content = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) { throw "Dosya icerigi bos." }
        $obj = $content | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj -or $null -eq $obj.profiles) { throw "Gecersiz profil semasi." }

        # Otomatik WinGet ID Cozumleme & Normalizasyon
        $appsData = Read-AppsJson
        if ($appsData -and $appsData.applications) {
            $aliasMap = @{
                "google-chrome"   = "Google.Chrome"
                "chrome"          = "Google.Chrome"
                "firefox"         = "Mozilla.Firefox"
                "vlc"             = "VideoLAN.VLC"
                "7zip"            = "7zip.7zip"
                "vscode"          = "Microsoft.VisualStudioCode"
                "notepadplusplus" = "Notepad++.Notepad++"
                "notepad++"       = "Notepad++.Notepad++"
            }
            foreach ($p in $obj.profiles) {
                if ($p.applications) {
                    $cleaned = [System.Collections.Generic.List[string]]::new()
                    foreach ($appId in $p.applications) {
                        $trimmedId = "$appId".Trim()
                        if ($aliasMap.ContainsKey($trimmedId.ToLower())) {
                            $canon = $aliasMap[$trimmedId.ToLower()]
                            if (-not $cleaned.Contains($canon)) { $cleaned.Add($canon) }
                        } else {
                            $match = $appsData.applications | Where-Object {
                                $_.Id -ieq $trimmedId -or $_.Name -ieq $trimmedId
                            } | Select-Object -First 1
                            $finalId = if ($match) { $match.Id } else { $trimmedId }
                            if (-not $cleaned.Contains($finalId)) { $cleaned.Add($finalId) }
                        }
                    }
                    $p.applications = $cleaned.ToArray()
                }
            }
        }

        return $obj
    } catch {
        Write-Host "  [UYARI] profiles.json okunamadi veya bozuk: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  [BILGI] En son gecerli yedekten otomatik kurtarma deneniyor..." -ForegroundColor Cyan

        $backupDir = Get-BackupDirPath
        if (Test-Path $backupDir) {
            $latestBackup = Get-ChildItem -Path $backupDir -Filter "profiles_backup_*.json" -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestBackup) {
                try {
                    $bRaw = Get-Content -Path $latestBackup.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                    $bObj = $bRaw | ConvertFrom-Json -ErrorAction Stop
                    if ($bObj -and $bObj.profiles) {
                        Write-Host "  [BASARILI] profiles.json yedege kurtarildi: $($latestBackup.Name)" -ForegroundColor Green
                        $corruptPath = $path + ".corrupt_" + (Get-Date -Format "yyyyMMdd_HHmmss")
                        Copy-Item -Path $path -Destination $corruptPath -Force -ErrorAction SilentlyContinue
                        $bRaw | Set-Content -Path $path -Encoding UTF8 -Force
                        return $bObj
                    }
                } catch {}
            }
        }

        return [PSCustomObject]@{
            version      = "1.0.0"
            last_updated = (Get-Date -Format "yyyy-MM-dd")
            profiles     = @()
        }
    }
}

function Write-ProfilesJson {
    param([Parameter(Mandatory)][object]$Data)
    $path = Get-ProfilesFilePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # 1. Her degisiklik oncesinde otomatik zaman damgali yedek olustur
    if (Test-Path $path) {
        $backupPath = New-ProfileBackup -SourcePath $path -Prefix "profiles"
        if ($backupPath) {
            Write-LogInfo "Profil degisikligi oncesi otomatik yedek alindi: $backupPath"
        }
    }

    # 2. Guvenli atomik kayit
    $tmpPath = $path + ".tmp"
    try {
        $Data.last_updated = (Get-Date -Format "yyyy-MM-dd")
        $json = $Data | ConvertTo-Json -Depth 10
        $json | Set-Content -Path $tmpPath -Encoding UTF8 -ErrorAction Stop
        # Dogrula
        $verify = Get-Content -Path $tmpPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $verify -or $null -eq $verify.profiles) { throw "JSON dogrulama basarisiz" }
        Move-Item -Path $tmpPath -Destination $path -Force
        return $true
    } catch {
        Write-Host "  [HATA] Kayit basarisiz: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function Read-AppsJson {
    $path = Get-AppsFilePath
    if (-not (Test-Path $path)) { return $null }
    try {
        $content = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop
        return $content | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "  [HATA] apps.json okunamadi: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Read-SettingsJson {
    $path = Get-SettingsFilePath
    if (-not (Test-Path $path)) { return $null }
    try {
        $content = Get-Content -Path $path -Raw -Encoding UTF8 -ErrorAction Stop
        return $content | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "  [HATA] settings.json okunamadi: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Write-SettingsJson {
    param([Parameter(Mandatory)][object]$Data)
    $path = Get-SettingsFilePath
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (Test-Path $path) {
        $null = New-ProfileBackup -SourcePath $path -Prefix "settings"
    }

    $tmpPath = $path + ".tmp"
    try {
        $Data.last_updated = (Get-Date -Format "yyyy-MM-dd")
        $json = $Data | ConvertTo-Json -Depth 10
        $json | Set-Content -Path $tmpPath -Encoding UTF8 -ErrorAction Stop
        $verify = Get-Content -Path $tmpPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $verify) { throw "JSON dogrulama basarisiz" }
        Move-Item -Path $tmpPath -Destination $path -Force
        return $true
    } catch {
        Write-Host "  [HATA] Ayar kayit basarisiz: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function New-ProfileBackup {
    param([string]$SourcePath, [string]$Prefix)
    $backupDir = Get-BackupDirPath
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ext = [System.IO.Path]::GetExtension($SourcePath)
    $backupName = "${Prefix}_backup_${stamp}${ext}"
    $backupPath = Join-Path $backupDir $backupName
    try {
        Copy-Item -Path $SourcePath -Destination $backupPath -Force -ErrorAction Stop
        return $backupPath
    } catch {
        return $null
    }
}

function Draw-Line {
    param([string]$Color = "DarkCyan", [int]$Width = 86, [string]$Char = "-")
    Write-Host ("  " + ($Char * [math]::Max(1, $Width))) -ForegroundColor $Color
}

function Show-ProfileHeader {
    param([string]$Title)
    Write-Host ""
    Draw-Line -Color Magenta -Char "="
    Write-Host ("  [PROFIL] " + $Title) -ForegroundColor Magenta
    Draw-Line -Color Magenta -Char "="
}

function Show-SettingsHeader {
    param([string]$Title)
    Write-Host ""
    Draw-Line -Color Cyan -Char "="
    Write-Host ("  [AYAR] " + $Title) -ForegroundColor Cyan
    Draw-Line -Color Cyan -Char "="
}

function Show-BackupHeader {
    param([string]$Title)
    Write-Host ""
    Draw-Line -Color DarkCyan -Char "="
    Write-Host ("  [YEDEK] " + $Title) -ForegroundColor DarkCyan
    Draw-Line -Color DarkCyan -Char "="
}

function Get-AppSelectionFromInput {
    <#
    .SYNOPSIS
        "1,3,5" veya "1-5" veya "hepsi" girisi alir, 0 tabanli benzersiz indeks listesi doner.
    #>
    param(
        [string]$SelectionString,
        [int]$MaxCount
    )
    if ([string]::IsNullOrWhiteSpace($SelectionString)) { return @() }
    $trimmed = $SelectionString.Trim().ToLower()
    if ($trimmed -in "hepsi", "tum", "all") {
        return @(0..($MaxCount - 1))
    }

    $indices = [System.Collections.Generic.List[int]]::new()
    $parts = $trimmed -split "[,;\s]+"
    foreach ($part in $parts) {
        $p = $part.Trim()
        if (-not $p) { continue }
        if ($p -match "^(\d+)-(\d+)$") {
            $start = [int]$Matches[1]
            $end   = [int]$Matches[2]
            if ($start -gt $end) { $tmp = $start; $start = $end; $end = $tmp }
            for ($i = $start; $i -le $end; $i++) {
                if ($i -ge 1 -and $i -le $MaxCount) {
                    if (-not $indices.Contains($i - 1)) { $indices.Add($i - 1) }
                }
            }
        } elseif ($p -match "^\d+$") {
            $n = [int]$p
            if ($n -ge 1 -and $n -le $MaxCount) {
                if (-not $indices.Contains($n - 1)) { $indices.Add($n - 1) }
            }
        }
    }
    return @($indices | Sort-Object)
}

#endregion

#region ─── PROFİL LİSTELEME ──────────────────────────────────────────────────

function Show-ProfileList {
    param([switch]$Detailed)
    $data = Read-ProfilesJson
    if (-not $data -or -not $data.profiles -or $data.profiles.Count -eq 0) {
        Write-Host "  Kayitli profil bulunamadi." -ForegroundColor Yellow
        return $null
    }
    $appsData = Read-AppsJson
    $appMap = @{}
    if ($appsData -and $appsData.applications) {
        foreach ($app in $appsData.applications) {
            $appMap[$app.Id] = $app
            $appMap[$app.id] = $app
        }
    }

    Write-Host ""
    Draw-Line -Color DarkCyan
    Write-Host ("  {0,-5} {1,-24} {2,-12} {3}" -f "No", "Profil Adi", "Prog. Sayisi", "Aciklama") -ForegroundColor White
    Draw-Line -Color DarkCyan

    $i = 1
    foreach ($p in $data.profiles) {
        $appCount = if ($p.applications) { $p.applications.Count } else { 0 }
        $desc = if ($p.description) { $p.description } else { "-" }
        if ($desc.Length -gt 35) { $desc = $desc.Substring(0, 32) + "..." }
        Write-Host ("  [{0,-2}] {1,-24} {2,-12} {3}" -f $i, $p.name, "$appCount program", $desc) -ForegroundColor Magenta

        if ($Detailed -and $p.applications -and $p.applications.Count -gt 0) {
            $k = 1
            foreach ($appId in $p.applications) {
                $appName = if ($appMap.ContainsKey($appId)) { $appMap[$appId].Name } else { $appId }
                Write-Host ("        {0,2}. {1,-28} [{2}]" -f $k, $appName, $appId) -ForegroundColor DarkCyan
                $k++
            }
        }
        $i++
    }
    Draw-Line -Color DarkCyan
    return $data
}

#endregion

#region ─── PROGRAM SEÇİM MENÜSÜ (KATEGORİ KATEGORİ) ──────────────────────────

function Select-ApplicationsFromCatalog {
    param(
        [string]$Title = "Program Secimi",
        [string[]]$AlreadySelected = @()
    )
    $appsData = Read-AppsJson
    if (-not $appsData -or -not $appsData.applications) {
        Write-Host "  [HATA] Uygulama katalogu okunamadi." -ForegroundColor Red
        return $null
    }

    $activeApps = @($appsData.applications | Where-Object { $_.Enabled -eq $true })
    if ($activeApps.Count -eq 0) {
        Write-Host "  Aktif uygulama bulunamadi." -ForegroundColor Yellow
        return @()
    }

    $categories = if ($appsData.categories) { @($appsData.categories) } else { @() }
    $catMap = @{}
    foreach ($cat in $categories) { $catMap[$cat.id] = $cat }

    $allSorted = [System.Collections.Generic.List[PSCustomObject]]::new()

    Show-ProfileHeader $Title
    Write-Host "  Secim Formati : '1,3,5' veya '2-6' veya 'hepsi' | [0] Iptal" -ForegroundColor Cyan
    Write-Host "  Mevcut Durum  : Zaten ekli olan programlar [* Ekli] olarak gosterilir." -ForegroundColor DarkGray
    Write-Host ""

    # Kategori Kategori Listele
    $grouped = $activeApps | Group-Object -Property Category
    $runningIdx = 1

    foreach ($grp in $grouped) {
        $catObj = if ($catMap.ContainsKey($grp.Name)) { $catMap[$grp.Name] } else { $null }
        $catIcon = if ($catObj -and $catObj.icon) { $catObj.icon } else { "📁" }
        $catName = if ($catObj -and $catObj.name) { $catObj.name } else { $grp.Name }

        Write-Host ""
        Write-Host "  $catIcon $catName ($($grp.Name))" -ForegroundColor Cyan
        Draw-Line -Color DarkCyan -Width 76
        Write-Host ("    {0,-5} {1,-30} {2,-24} {3}" -f "No", "Program Adi", "WinGet ID", "Durum") -ForegroundColor DarkCyan

        foreach ($app in $grp.Group) {
            $allSorted.Add($app)

            $isAlready = ($AlreadySelected -contains $app.Id -or $AlreadySelected -contains $app.id)
            $marker = if ($isAlready) { "[* Ekli]" } else { "[      ]" }
            $markerColor = if ($isAlready) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkGray }

            $numTag = "[{0,2}]" -f $runningIdx
            $nameStr = if ($app.Name.Length -gt 28) { $app.Name.Substring(0,25) + "..." } else { $app.Name }
            $idStr   = if ($app.Id.Length -gt 22)   { $app.Id.Substring(0,19) + "..."   } else { $app.Id }

            Write-Host ("    $numTag ") -ForegroundColor Yellow -NoNewline
            Write-Host ("{0,-30} " -f $nameStr) -ForegroundColor White -NoNewline
            Write-Host ("{0,-24} " -f $idStr) -ForegroundColor Cyan -NoNewline
            Write-Host $marker -ForegroundColor $markerColor

            $runningIdx++
        }
    }
    Draw-Line -Color DarkCyan -Width 76
    Write-Host ("  Toplam: {0} aktif program listelendi." -f $allSorted.Count) -ForegroundColor White

    while ($true) {
        Write-Host ""
        $inputStr = Read-Host "  Seciminiz (ornek: 1,3,5 veya 2-6 veya hepsi | 0=Iptal)"
        if ($inputStr.Trim() -eq "0") { return $null }
        if ([string]::IsNullOrWhiteSpace($inputStr)) { continue }

        $indices = Get-AppSelectionFromInput -SelectionString $inputStr -MaxCount $allSorted.Count
        if ($indices.Count -eq 0) {
            Write-Host "  Gecersiz secim. Lutfen gecerli bir aralik veya numara girin." -ForegroundColor Yellow
            continue
        }

        $selectedApps = @()
        foreach ($idx in $indices) {
            $selectedApps += $allSorted[$idx]
        }

        Write-Host ""
        Write-Host ("  Secilen Programlar ({0} adet):" -f $selectedApps.Count) -ForegroundColor Green
        Draw-Line -Color DarkCyan
        foreach ($app in $selectedApps) {
            Write-Host ("    • {0,-30} ({1})" -f $app.Name, $app.Id) -ForegroundColor White
        }
        Draw-Line -Color DarkCyan

        $confirm = Read-Host "  Bu secimi onayliyor musunuz? [E/h]"
        if ($confirm -match "^[Hh]") { continue }

        # WinGet Paket Kimlikleriyle (Id) dondur
        return @($selectedApps | ForEach-Object { $_.Id })
    }
}

#endregion

#region ─── PROFİL İŞLEMLERİ: CRUD, SIRALAMA VE KURULUM ───────────────────────

function Invoke-ListProfiles {
    Show-ProfileHeader "Profil Listesi"
    $data = Show-ProfileList -Detailed
    if ($data -and $data.profiles.Count -gt 0) {
        Write-Host ""
        $choice = Read-Host "  Detay incelemek icin profil numarasi girin veya Enter ile devam edin"
        if ($choice -match "^\d+$") {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $data.profiles.Count) {
                $p = $data.profiles[$idx]
                Show-ProfileHeader ("Profil Detayi: " + $p.name)
                Write-Host ("  ID         : {0}" -f $p.id) -ForegroundColor White
                Write-Host ("  Ad         : {0}" -f $p.name) -ForegroundColor White
                Write-Host ("  Aciklama   : {0}" -f $p.description) -ForegroundColor White
                Write-Host ("  Olusturma  : {0}" -f $p.created) -ForegroundColor White
                Write-Host ("  Durum      : {0}" -f $(if ($p.enabled) { "Aktif" } else { "Pasif" })) -ForegroundColor White
                Write-Host ""
                Write-Host ("  Programlar ({0} adet):" -f $p.applications.Count) -ForegroundColor Magenta

                $appsData = Read-AppsJson
                $appMap = @{}
                if ($appsData -and $appsData.applications) {
                    foreach ($app in $appsData.applications) {
                        $appMap[$app.Id] = $app
                        $appMap[$app.id] = $app
                    }
                }

                if (-not $p.applications -or $p.applications.Count -eq 0) {
                    Write-Host "    (Bu profilde henuz program bulunmuyor)" -ForegroundColor Gray
                } else {
                    $k = 1
                    foreach ($appId in $p.applications) {
                        $appObj = if ($appMap.ContainsKey($appId)) { $appMap[$appId] } else { $null }
                        $appName = if ($appObj) { $appObj.Name } else { $appId }
                        $cat = if ($appObj) { "[$($appObj.Category)]" } else { "" }

                        # Kurulum kontrolu
                        $statusBadge = ""
                        if (Get-Command "Test-AppInstalled" -ErrorAction SilentlyContinue) {
                            $chk = Test-AppInstalled -PackageId $appId
                            if ($chk.IsInstalled) {
                                $vStr = if ($chk.InstalledVersion) { " v$($chk.InstalledVersion)" } else { "" }
                                $statusBadge = " [KURULU$vStr]"
                            }
                        }

                        $bColor = if ($statusBadge) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkCyan }
                        Write-Host ("    [{0,2}] {1,-28} {2,-24}" -f $k, $appName, $appId) -ForegroundColor White -NoNewline
                        Write-Host $statusBadge -ForegroundColor $bColor
                        $k++
                    }
                }
                Draw-Line -Color DarkCyan
                Read-Host "  Devam etmek icin Enter'a basin"
            }
        }
    } else {
        Read-Host "  Devam etmek icin Enter'a basin"
    }
}

function Invoke-CreateProfile {
    Show-ProfileHeader "Yeni Profil Olustur"
    $data = Read-ProfilesJson
    if (-not $data) { return }

    # Adim 1: ID
    while ($true) {
        Write-Host "  [Adim 1/4] Profil ID (kucuk harf, bosluksuz, orn: yazilim_gelistirici)" -ForegroundColor Magenta
        Write-Host "  Iptal icin 0 girin." -ForegroundColor Gray
        $id = Read-Host "  Profil ID"
        if ($id -eq "0") { return }
        if ([string]::IsNullOrWhiteSpace($id)) { Write-Host "  ID bos olamaz." -ForegroundColor Yellow; continue }
        $id = $id.Trim().ToLower() -replace '[^a-z0-9_\-]', '_'
        $exists = $data.profiles | Where-Object { $_.id -eq $id }
        if ($exists) { Write-Host ("  Bu ID zaten var: '{0}'. Lutfen farkli bir ID girin." -f $id) -ForegroundColor Yellow; continue }
        break
    }

    # Adim 2: Ad
    while ($true) {
        Write-Host ""
        Write-Host "  [Adim 2/4] Profil Gorunen Adi" -ForegroundColor Magenta
        $name = Read-Host "  Profil Adi (0=Iptal)"
        if ($name -eq "0") { return }
        if (-not [string]::IsNullOrWhiteSpace($name)) { break }
        Write-Host "  Profil adi bos olamaz." -ForegroundColor Yellow
    }

    # Adim 3: Aciklama
    Write-Host ""
    Write-Host "  [Adim 3/4] Profil Aciklamasi (opsiyonel)" -ForegroundColor Magenta
    $desc = Read-Host "  Aciklama"

    # Adim 4: Program secimi
    Write-Host ""
    Write-Host "  [Adim 4/4] Program Secimi" -ForegroundColor Magenta
    $addNow = Read-Host "  Profile simdi program eklemek istiyor musunuz? [E/h]"
    $selectedIds = @()
    if ($addNow -notmatch "^[Hh]") {
        $selectedIds = Select-ApplicationsFromCatalog -Title "Yeni Profile Program Ekle"
        if ($null -eq $selectedIds) { $selectedIds = @() }
    }

    # Ozet
    Show-ProfileHeader "Profil Ozeti"
    Write-Host ("  ID       : {0}" -f $id) -ForegroundColor White
    Write-Host ("  Ad       : {0}" -f $name) -ForegroundColor White
    Write-Host ("  Aciklama : {0}" -f $(if ($desc) { $desc } else { "(bos)" })) -ForegroundColor White
    Write-Host ("  Program  : {0} adet secildi" -f $selectedIds.Count) -ForegroundColor White
    Draw-Line -Color DarkCyan
    $confirm = Read-Host "  Profili kaydetmek istiyor musunuz? [E/h]"
    if ($confirm -match "^[Hh]") { Write-Host "  Profil olusturma iptal edildi." -ForegroundColor Yellow; return }

    # Mukerrer ID kontrolu
    $cleanedIds = [System.Collections.Generic.List[string]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pkg in $selectedIds) {
        if (-not $seenIds.Contains($pkg)) {
            $cleanedIds.Add($pkg)
            $seenIds.Add($pkg) | Out-Null
        }
    }

    $newProfile = [PSCustomObject]@{
        id           = $id
        name         = $name
        description  = $desc
        applications = $cleanedIds.ToArray()
        created      = (Get-Date -Format "yyyy-MM-dd")
        enabled      = $true
    }

    $profilesList = [System.Collections.ArrayList]@($data.profiles)
    $profilesList.Add($newProfile) | Out-Null
    $data.profiles = $profilesList.ToArray()

    if (Write-ProfilesJson -Data $data) {
        Write-Host ""
        Write-Host ("  [BASARILI] '{0}' profili basariyla olusturuldu ve JSON dosyasina kaydedildi." -f $name) -ForegroundColor Green
    }
    Read-Host "  Devam etmek icin Enter'a basin"
}

function Invoke-EditProfileMeta {
    Show-ProfileHeader "Profil Adini ve Aciklamasini Duzenle"
    $data = Show-ProfileList
    if (-not $data -or $data.profiles.Count -eq 0) { Read-Host "  Devam etmek icin Enter'a basin"; return }

    $choice = Read-Host "  Duzenlenecek profil numarasi (0=Geri)"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $data.profiles.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }

    $p = $data.profiles[$idx]
    Draw-Line -Color DarkCyan
    Write-Host ("  Mevcut Ad       : {0}" -f $p.name) -ForegroundColor White
    Write-Host ("  Mevcut Aciklama : {0}" -f $p.description) -ForegroundColor White
    Draw-Line -Color DarkCyan

    $newName = Read-Host ("  Yeni Ad [{0}] (bos birak=ayni kalsin)" -f $p.name)
    $newDesc = Read-Host ("  Yeni Aciklama [{0}] (bos birak=ayni kalsin)" -f $p.description)

    if ([string]::IsNullOrWhiteSpace($newName) -and [string]::IsNullOrWhiteSpace($newDesc)) {
        Write-Host "  Hicbir degisiklik yapilmadi." -ForegroundColor Yellow
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    Write-Host ""
    Write-Host "  Degisiklik Ozeti:" -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($newName)) {
        Write-Host ("    Ad       : {0}  =>  {1}" -f $p.name, $newName) -ForegroundColor White
    }
    if (-not [string]::IsNullOrWhiteSpace($newDesc)) {
        Write-Host ("    Aciklama : {0}  =>  {1}" -f $p.description, $newDesc) -ForegroundColor White
    }

    $confirm = Read-Host "  Degisiklikleri onayliyor musunuz? [E/h]"
    if ($confirm -match "^[Hh]") { Write-Host "  Duzenleme iptal edildi." -ForegroundColor Yellow; Read-Host "  Enter"; return }

    if (-not [string]::IsNullOrWhiteSpace($newName))  { $data.profiles[$idx].name        = $newName }
    if (-not [string]::IsNullOrWhiteSpace($newDesc))  { $data.profiles[$idx].description = $newDesc }

    if (Write-ProfilesJson -Data $data) {
        Write-Host "  [BASARILI] Profil bilgileri guncellendi ve kaydedildi." -ForegroundColor Green
    }
    Read-Host "  Devam etmek icin Enter'a basin"
}

function Invoke-AddAppsToProfile {
    Show-ProfileHeader "Profile Program Ekle"
    $data = Show-ProfileList
    if (-not $data -or $data.profiles.Count -eq 0) { Read-Host "  Devam etmek icin Enter'a basin"; return }

    $choice = Read-Host "  Program eklenecek profil numarasi (0=Geri)"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $data.profiles.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }

    $p = $data.profiles[$idx]
    $existing = if ($p.applications) { @($p.applications) } else { @() }

    $newIds = Select-ApplicationsFromCatalog -Title ("Profile Ekle: " + $p.name) -AlreadySelected $existing
    if ($null -eq $newIds -or $newIds.Count -eq 0) {
        Write-Host "  Islem iptal edildi veya program secilmedi." -ForegroundColor Yellow
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    $existingLower = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ex in $existing) { $existingLower.Add($ex) | Out-Null }

    $combined = [System.Collections.Generic.List[string]]::new([string[]]$existing)
    $addedList = [System.Collections.Generic.List[string]]::new()
    $duplicateCount = 0

    foreach ($appId in $newIds) {
        if (-not $existingLower.Contains($appId)) {
            $combined.Add($appId)
            $existingLower.Add($appId) | Out-Null
            $addedList.Add($appId)
        } else {
            $duplicateCount++
        }
    }

    if ($addedList.Count -eq 0) {
        Write-Host "  [BILGI] Secilen tum programlar zaten profilde mevcut." -ForegroundColor Yellow
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    $data.profiles[$idx].applications = $combined.ToArray()
    if (Write-ProfilesJson -Data $data) {
        Write-Host ""
        Write-Host ("  [BASARILI] {0} yeni program '{1}' profiline eklendi ve JSON dosyasina kaydedildi." -f $addedList.Count, $p.name) -ForegroundColor Green
        if ($duplicateCount -gt 0) {
            Write-Host ("  [BILGI] {0} program zaten profilde mevcut oldugundan mukerrer eklenmedi." -f $duplicateCount) -ForegroundColor DarkCyan
        }
    }
    Read-Host "  Devam etmek icin Enter'a basin"
}

function Invoke-RemoveAppsFromProfile {
    Show-ProfileHeader "Profilden Program Cikar"
    $data = Show-ProfileList
    if (-not $data -or $data.profiles.Count -eq 0) { Read-Host "  Devam etmek icin Enter'a basin"; return }

    $choice = Read-Host "  Program cikarilacak profil numarasi (0=Geri)"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $data.profiles.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }

    $p = $data.profiles[$idx]
    if (-not $p.applications -or $p.applications.Count -eq 0) {
        Write-Host ("  '{0}' profilinde cikarilacak hic program yok." -f $p.name) -ForegroundColor Yellow
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    $appsData = Read-AppsJson
    $appMap = @{}
    if ($appsData -and $appsData.applications) {
        foreach ($app in $appsData.applications) {
            $appMap[$app.Id] = $app
            $appMap[$app.id] = $app
        }
    }

    Write-Host ""
    Write-Host "  [ONEMLI BILGI] Bu islem yalnizca profilden cikarir; bilgisayardan programi KALDIRMAZ." -ForegroundColor Cyan
    Write-Host ""
    Show-ProfileHeader ("Profildeki Programlar: " + $p.name)
    Draw-Line -Color DarkCyan
    Write-Host ("    {0,-5} {1,-32} {2}" -f "No", "Program Adi", "WinGet ID") -ForegroundColor White
    Draw-Line -Color DarkCyan
    for ($i = 0; $i -lt $p.applications.Count; $i++) {
        $appId   = $p.applications[$i]
        $appName = if ($appMap.ContainsKey($appId)) { $appMap[$appId].Name } else { $appId }
        Write-Host ("    [{0,-2}] {1,-32} {2}" -f ($i+1), $appName, $appId) -ForegroundColor Magenta
    }
    Draw-Line -Color DarkCyan
    Write-Host "  Birden fazla secim: '1,3' veya '2-4' veya 'hepsi' | 0=Geri" -ForegroundColor Gray
    Write-Host ""

    $removeInput = Read-Host "  Cikarilacak program numaralari"
    if ($removeInput.Trim() -eq "0" -or [string]::IsNullOrWhiteSpace($removeInput)) { return }

    $removeIndices = Get-AppSelectionFromInput -SelectionString $removeInput -MaxCount $p.applications.Count
    if ($removeIndices.Count -eq 0) {
        Write-Host "  Gecersiz secim." -ForegroundColor Yellow
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    $toRemove = [System.Collections.Generic.List[string]]::new()
    foreach ($ri in $removeIndices) { $toRemove.Add($p.applications[$ri]) }

    Write-Host ""
    Write-Host "  Profilden Cikarilacak Programlar:" -ForegroundColor Yellow
    foreach ($appId in $toRemove) {
        $appName = if ($appMap.ContainsKey($appId)) { $appMap[$appId].Name } else { $appId }
        Write-Host ("    - {0} [{1}]" -f $appName, $appId) -ForegroundColor White
    }

    $confirm = Read-Host "  Bu programlari profilden cikarmayi onayliyor musunuz? [E/h]"
    if ($confirm -match "^[Hh]") { Write-Host "  Cikarma iptal edildi." -ForegroundColor Yellow; Read-Host "  Enter"; return }

    $toRemoveLower = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($tr in $toRemove) { $toRemoveLower.Add($tr) | Out-Null }

    $remaining = @($p.applications | Where-Object { -not $toRemoveLower.Contains($_) })
    $data.profiles[$idx].applications = $remaining

    if (Write-ProfilesJson -Data $data) {
        Write-Host ("  [BASARILI] {0} program '{1}' profilinden basariyla cikarildi." -f $toRemove.Count, $p.name) -ForegroundColor Green
    }
    Read-Host "  Devam etmek icin Enter'a basin"
}

function Invoke-ReorderProfileApps {
    Show-ProfileHeader "Profildeki Programlarin Sirasini Degistir"
    $data = Show-ProfileList
    if (-not $data -or $data.profiles.Count -eq 0) {
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    $choice = Read-Host "  Sirasi degistirilecek profil numarasi (0=Geri)"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $data.profiles.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }

    $p = $data.profiles[$idx]
    if (-not $p.applications -or $p.applications.Count -le 1) {
        Write-Host ("  '{0}' profilinde siralanacak yeterli program yok (en az 2 program gereklidir)." -f $p.name) -ForegroundColor Yellow
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    $appsData = Read-AppsJson
    $appMap = @{}
    if ($appsData -and $appsData.applications) {
        foreach ($app in $appsData.applications) {
            $appMap[$app.Id] = $app
            $appMap[$app.id] = $app
        }
    }

    $currentApps = @($p.applications)
    Write-Host ""
    Write-Host "  Mevcut Program Sirasi:" -ForegroundColor Cyan
    Draw-Line -Color DarkCyan
    for ($i = 0; $i -lt $currentApps.Count; $i++) {
        $appId = $currentApps[$i]
        $appName = if ($appMap.ContainsKey($appId)) { $appMap[$appId].Name } else { $appId }
        Write-Host ("    [{0}] {1,-30} ({2})" -f ($i+1), $appName, $appId) -ForegroundColor White
    }
    Draw-Line -Color DarkCyan
    Write-Host ""
    Write-Host "  Siralama Yontemi Secin:" -ForegroundColor Yellow
    Write-Host "    [1] Yeni tam sira dizisini gir (ornek: 3,1,2,4)" -ForegroundColor White
    Write-Host "    [2] Tek bir programi yeni konuma tasi (ornek: 4 numarayi 1. konuma)" -ForegroundColor White
    Write-Host "    [0] Iptal" -ForegroundColor DarkCyan
    Write-Host ""
    $mChoice = Read-Host "  Seciminiz [1, 2 veya 0]"

    $newAppOrder = $null

    if ($mChoice -eq "1") {
        Write-Host ""
        Write-Host ("  1'den {0}'e kadar olan numaralari yeni sirayla girin (ornek: 2,1,3):" -f $currentApps.Count) -ForegroundColor Yellow
        $seqInput = Read-Host "  Yeni Sira"
        if ($seqInput -eq "0" -or [string]::IsNullOrWhiteSpace($seqInput)) { return }

        $parts = $seqInput -split "[,;\s]+" | Where-Object { $_ -match "^\d+$" }
        if ($parts.Count -ne $currentApps.Count) {
            Write-Host ("  [HATA] Tam olarak {0} adet numara girmelisiniz!" -f $currentApps.Count) -ForegroundColor Red
            Read-Host "  Devam etmek icin Enter'a basin"; return
        }

        $seen = [System.Collections.Generic.HashSet[int]]::new()
        $tempList = [System.Collections.Generic.List[string]]::new()
        $valid = $true
        foreach ($pt in $parts) {
            $num = [int]$pt
            if ($num -lt 1 -or $num -gt $currentApps.Count -or $seen.Contains($num)) {
                $valid = $false; break
            }
            $seen.Add($num) | Out-Null
            $tempList.Add($currentApps[$num - 1])
        }

        if (-not $valid) {
            Write-Host "  [HATA] Gecersiz veya tekrarlayan sira numarasi girdiniz!" -ForegroundColor Red
            Read-Host "  Devam etmek icin Enter'a basin"; return
        }

        $newAppOrder = $tempList.ToArray()

    } elseif ($mChoice -eq "2") {
        Write-Host ""
        $srcNumStr = Read-Host "  Tasinacak programin mevcut sira numarasi (1-$($currentApps.Count))"
        if ($srcNumStr -notmatch "^\d+$") { return }
        $srcNum = [int]$srcNumStr
        if ($srcNum -lt 1 -or $srcNum -gt $currentApps.Count) {
            Write-Host "  [HATA] Gecersiz sira numarasi." -ForegroundColor Red; return
        }

        $dstNumStr = Read-Host "  Tasinacagi yeni sira numarasi (1-$($currentApps.Count))"
        if ($dstNumStr -notmatch "^\d+$") { return }
        $dstNum = [int]$dstNumStr
        if ($dstNum -lt 1 -or $dstNum -gt $currentApps.Count) {
            Write-Host "  [HATA] Gecersiz hedef numarasi." -ForegroundColor Red; return
        }

        if ($srcNum -eq $dstNum) {
            Write-Host "  Ayni sira numarasi secildi, degisiklik yapilmadi." -ForegroundColor Yellow
            Read-Host "  Enter"; return
        }

        $list = [System.Collections.Generic.List[string]]::new([string[]]$currentApps)
        $itemToMove = $list[$srcNum - 1]
        $list.RemoveAt($srcNum - 1)
        $list.Insert($dstNum - 1, $itemToMove)
        $newAppOrder = $list.ToArray()
    } else {
        return
    }

    if ($newAppOrder) {
        Write-Host ""
        Write-Host "  Yeni Program Sirasi:" -ForegroundColor Green
        Draw-Line -Color DarkCyan
        for ($i = 0; $i -lt $newAppOrder.Count; $i++) {
            $appId = $newAppOrder[$i]
            $appName = if ($appMap.ContainsKey($appId)) { $appMap[$appId].Name } else { $appId }
            Write-Host ("    [{0}] {1,-30} ({2})" -f ($i+1), $appName, $appId) -ForegroundColor Green
        }
        Draw-Line -Color DarkCyan

        $conf = Read-Host "  Bu yeni siralamayi kaydetmek istiyor musunuz? [E/h]"
        if ($conf -match "^[Hh]") { Write-Host "  Iptal edildi." -ForegroundColor Yellow; return }

        $data.profiles[$idx].applications = $newAppOrder
        if (Write-ProfilesJson -Data $data) {
            Write-Host "  [BASARILI] Program sirasi basariyla guncellendi ve kaydedildi." -ForegroundColor Green
        }
        Read-Host "  Devam etmek icin Enter'a basin"
    }
}

function Invoke-CopyProfile {
    Show-ProfileHeader "Profil Kopyala"
    $data = Show-ProfileList
    if (-not $data -or $data.profiles.Count -eq 0) { Read-Host "  Devam etmek icin Enter'a basin"; return }

    $choice = Read-Host "  Kopyalanacak profil numarasi (0=Geri)"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $data.profiles.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }

    $source = $data.profiles[$idx]
    Write-Host ("  Kaynak: {0} ({1})" -f $source.name, $source.id) -ForegroundColor Cyan

    # Yeni ID
    while ($true) {
        $newId = Read-Host "  Yeni Profil ID (0=Iptal)"
        if ($newId -eq "0") { return }
        if ([string]::IsNullOrWhiteSpace($newId)) { Write-Host "  ID bos olamaz." -ForegroundColor Yellow; continue }
        $newId = $newId.Trim().ToLower() -replace '[^a-z0-9_\-]', '_'
        $exists = $data.profiles | Where-Object { $_.id -eq $newId }
        if ($exists) { Write-Host ("  Bu ID zaten var: '{0}'" -f $newId) -ForegroundColor Yellow; continue }
        break
    }

    $newName = Read-Host ("  Yeni Profil Adi [{0} - Kopya]" -f $source.name)
    if ([string]::IsNullOrWhiteSpace($newName)) { $newName = $source.name + " - Kopya" }

    $copyApps = if ($source.applications) { @($source.applications) } else { @() }

    $confirm = Read-Host ("  '{0}' profilini '{1}' olarak kopyalamayi onayliyor musunuz? [E/h]" -f $source.name, $newName)
    if ($confirm -match "^[Hh]") { Write-Host "  Iptal edildi." -ForegroundColor Yellow; Read-Host "  Enter"; return }

    $newProfile = [PSCustomObject]@{
        id           = $newId
        name         = $newName
        description  = $source.description + " (Kopya)"
        applications = $copyApps
        created      = (Get-Date -Format "yyyy-MM-dd")
        enabled      = $true
    }

    $profilesList = [System.Collections.ArrayList]@($data.profiles)
    $profilesList.Add($newProfile) | Out-Null
    $data.profiles = $profilesList.ToArray()

    if (Write-ProfilesJson -Data $data) {
        Write-Host ("  [BASARILI] '{0}' profili '{1}' olarak basariyla kopyalandi." -f $source.name, $newName) -ForegroundColor Green
    }
    Read-Host "  Devam etmek icin Enter'a basin"
}

function Invoke-DeleteProfile {
    Show-ProfileHeader "Profil Sil"
    $data = Show-ProfileList
    if (-not $data -or $data.profiles.Count -eq 0) { Read-Host "  Devam etmek icin Enter'a basin"; return }

    $choice = Read-Host "  Silinecek profil numarasi (0=Geri)"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $data.profiles.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }

    $p = $data.profiles[$idx]
    Draw-Line -Color Red -Char "!"
    Write-Host ("  UYARI: '{0}' profili kalici olarak silinecektir!" -f $p.name) -ForegroundColor Red
    Write-Host ("  Profil ID    : {0}" -f $p.id) -ForegroundColor White
    Write-Host ("  Program Sayisi: {0} adet" -f $p.applications.Count) -ForegroundColor White
    Draw-Line -Color Red -Char "!"

    $confirm1 = Read-Host "  Silmek istediginizden emin misiniz? [E/h]"
    if ($confirm1 -notmatch "^[Ee]") { Write-Host "  Silme islemi iptal edildi." -ForegroundColor Yellow; Read-Host "  Enter"; return }

    # Sadece hedeflenen profili cikar, diger tum profilleri aynen koru
    $newProfiles = @($data.profiles | Where-Object { $_.id -ne $p.id })
    $data.profiles = $newProfiles

    if (Write-ProfilesJson -Data $data) {
        Write-Host ("  [BASARILI] '{0}' profili basariyla silindi. Diger profiller korundu." -f $p.name) -ForegroundColor Green
    }
    Read-Host "  Devam etmek icin Enter'a basin"
}

function Invoke-InstallProfile {
    Show-ProfileHeader "Profil Uzerinden Toplu Kurulum Baslat"
    $data = Show-ProfileList
    if (-not $data -or $data.profiles.Count -eq 0) {
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    $choice = Read-Host "  Kurulum yapilacak profil numarasi (0=Geri)"
    if ($choice -eq "0" -or [string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }
    $idx = [int]$choice - 1
    if ($idx -lt 0 -or $idx -ge $data.profiles.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; Start-Sleep -Seconds 1; return }

    $p = $data.profiles[$idx]
    if (-not $p.applications -or $p.applications.Count -eq 0) {
        Write-Host ("  '{0}' profilinde hic program tanimli degil!" -f $p.name) -ForegroundColor Yellow
        Read-Host "  Devam etmek icin Enter'a basin"; return
    }

    $appsData = Read-AppsJson
    $catalogApps = if ($appsData -and $appsData.applications) { @($appsData.applications) } else { @() }

    $appsToInstall = [System.Collections.Generic.List[PSCustomObject]]::new()
    $order = 1
    foreach ($appId in $p.applications) {
        $found = $catalogApps | Where-Object {
            $_.Id -ieq $appId -or $_.id -ieq $appId -or $_.winget_id -ieq $appId
        } | Select-Object -First 1

        if ($found) {
            $appsToInstall.Add($found)
        } else {
            $customApp = [PSCustomObject]@{
                Id            = $appId
                winget_id     = $appId
                Name          = $appId
                Publisher     = "WinGet"
                Source        = "winget"
                Architecture  = "x64"
                Scope         = "machine"
                SilentInstall = $true
                InstallOrder  = $order
                Enabled       = $true
            }
            $appsToInstall.Add($customApp)
        }
        $order++
    }

    Write-Host ""
    Write-Host ("  [PROFIL ONAYI] '{0}' Profilindeki Programlar:" -f $p.name) -ForegroundColor Cyan
    Draw-Line -Color DarkCyan
    for ($k = 0; $k -lt $appsToInstall.Count; $k++) {
        $item = $appsToInstall[$k]
        Write-Host ("    [{0,2}] {1,-30} ({2})" -f ($k+1), $item.Name, $item.Id) -ForegroundColor White
    }
    Draw-Line -Color DarkCyan
    Write-Host ""

    $conf = Read-Host ("  '{0}' profilindeki {1} programin kurulumunu baslatmak istiyor musunuz? [E/h]" -f $p.name, $appsToInstall.Count)
    if ($conf -match "^[Hh]") {
        Write-Host "  Kurulum iptal edildi." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        return
    }

    Write-Host ""
    Write-Host "  Mevcut WinGet kurulum motoru baslatiliyor, lutfen bekleyin..." -ForegroundColor Green
    Start-Sleep -Milliseconds 500

    if ($appsToInstall.Count -eq 1 -and (Get-Command "Invoke-WinGetInstall" -ErrorAction SilentlyContinue)) {
        # Tekli kurulum motoru
        $res = Invoke-WinGetInstall -App $appsToInstall[0] -IsBulkMode:$false
        if (Get-Command "Show-InstallReport" -ErrorAction SilentlyContinue) {
            Show-InstallReport -Results @(@{ App = $appsToInstall[0]; Result = $res }) -Title ("PROFIL KURULUM RAPORU: " + $p.name)
        }
    } elseif (Get-Command "Invoke-BulkInstall" -ErrorAction SilentlyContinue) {
        # Toplu kurulum motoru
        $bulkResults = Invoke-BulkInstall -Apps $appsToInstall
        if (Get-Command "Show-InstallReport" -ErrorAction SilentlyContinue) {
            Show-InstallReport -Results $bulkResults -Title ("PROFIL KURULUM RAPORU: " + $p.name)
        }
    } elseif (Get-Command "Invoke-WinGetInstall" -ErrorAction SilentlyContinue) {
        $results = @()
        foreach ($app in $appsToInstall) {
            $res = Invoke-WinGetInstall -App $app
            $results += @{ App = $app; Result = $res }
        }
        if (Get-Command "Show-InstallReport" -ErrorAction SilentlyContinue) {
            Show-InstallReport -Results $results -Title ("PROFIL KURULUM RAPORU: " + $p.name)
        }
    } else {
        Write-Host "  [HATA] WinGet kurulum motoru bulunamadi!" -ForegroundColor Red
        Read-Host "  Devam etmek icin Enter'a basin"
    }
}

function Invoke-ProfileManagement {
    while ($true) {
        Show-ProfileHeader "Profil Yonetim ve Kurulum Merkezi"
        Write-Host "  [1] Profilleri Listele (Program Detayli)" -ForegroundColor White
        Write-Host "  [2] Yeni Profil Olustur" -ForegroundColor White
        Write-Host "  [3] Profil Adini ve Aciklamasini Duzenle" -ForegroundColor White
        Write-Host "  [4] Profile Program Ekle (Kategorili Katalog)" -ForegroundColor White
        Write-Host "  [5] Profilden Program Cikar" -ForegroundColor White
        Write-Host "  [6] Profildeki Programlarin Sirasini Degistir" -ForegroundColor White
        Write-Host "  [7] Profil Kopyala (Cogalt)" -ForegroundColor White
        Write-Host "  [8] Profil Sil" -ForegroundColor White
        Draw-Line -Color DarkCyan
        Write-Host "  [K] Profil Uzerinden Toplu Kurulum Baslat" -ForegroundColor Green
        Draw-Line -Color DarkCyan
        Write-Host "  [0] Yonetici Paneline Don" -ForegroundColor Red
        Write-Host ""
        $choice = Read-Host "  Seciminiz"
        $ch = if ($null -ne $choice) { $choice.Trim().ToUpper() } else { "" }

        switch ($ch) {
            "1" { Invoke-ListProfiles }
            "2" { Invoke-CreateProfile }
            "3" { Invoke-EditProfileMeta }
            "4" { Invoke-AddAppsToProfile }
            "5" { Invoke-RemoveAppsFromProfile }
            "6" { Invoke-ReorderProfileApps }
            "7" { Invoke-CopyProfile }
            "8" { Invoke-DeleteProfile }
            "K" { Invoke-InstallProfile }
            "0" { return }
            "00" { return }
            default { Write-Host "  Gecersiz secim." -ForegroundColor Yellow; Start-Sleep -Milliseconds 600 }
        }
    }
}

#endregion

#region ─── AYAR YÖNETİMİ: Invoke-SettingsManagement ─────────────────────────

function Show-SettingChange {
    param([string]$Label, $OldVal, $NewVal)
    Write-Host ("  {0,-30} : {1}  =>  {2}" -f $Label, $OldVal, $NewVal) -ForegroundColor White
}

function Invoke-InstallSettings {
    Show-SettingsHeader "Kurulum Ayarlari"
    $settings = Read-SettingsJson
    if (-not $settings) { Write-Host "  [HATA] Ayar dosyasi okunamadi." -ForegroundColor Red; Read-Host "  Enter"; return }

    $inst = $settings.installation
    Draw-Line -Color Cyan
    Write-Host ("  Scope           : {0}" -f $inst.default_install_scope) -ForegroundColor White
    Write-Host ("  Mimari          : {0}" -f $inst.default_architecture) -ForegroundColor White
    Write-Host ("  Sessiz Kurulum  : {0}" -f $inst.silent_install) -ForegroundColor White
    Write-Host ("  Kurulum Dogrula : {0}" -f $inst.verify_after_install) -ForegroundColor White
    Write-Host ("  Tekrar Dene     : {0} (max {1} kez)" -f $inst.retry_on_failure, $inst.retry_count) -ForegroundColor White
    Draw-Line -Color Cyan

    Write-Host "  [1] Scope degistir  [2] Mimari degistir  [3] Sessiz kur aç/kapat"
    Write-Host "  [4] Dogrulama aç/kapat  [5] Tekrar deneme aç/kapat  [6] Tekrar sayisi"
    Write-Host "  [0] Geri"
    $sub = Read-Host "  Seciminiz"

    switch ($sub) {
        "1" {
            Write-Host "  [1] user   [2] machine" -ForegroundColor Cyan
            $s = Read-Host "  Yeni scope"
            $newScope = switch ($s) { "1" { "user" } "2" { "machine" } default { $null } }
            if ($newScope) {
                Show-SettingChange "Scope" $inst.default_install_scope $newScope
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.installation.default_install_scope = $newScope
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            }
        }
        "2" {
            Write-Host "  [1] x64  [2] x86  [3] arm64  [4] any" -ForegroundColor Cyan
            $s = Read-Host "  Yeni mimari"
            $newArch = switch ($s) { "1" { "x64" } "2" { "x86" } "3" { "arm64" } "4" { "any" } default { $null } }
            if ($newArch) {
                Show-SettingChange "Mimari" $inst.default_architecture $newArch
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.installation.default_architecture = $newArch
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            }
        }
        "3" {
            $newVal = -not $inst.silent_install
            Show-SettingChange "Sessiz Kurulum" $inst.silent_install $newVal
            $ok = Read-Host "  Onay? [E/h]"
            if ($ok -notmatch "^[Hh]") {
                $settings.installation.silent_install = $newVal
                if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
            }
        }
        "4" {
            $newVal = -not $inst.verify_after_install
            Show-SettingChange "Dogrulama" $inst.verify_after_install $newVal
            $ok = Read-Host "  Onay? [E/h]"
            if ($ok -notmatch "^[Hh]") {
                $settings.installation.verify_after_install = $newVal
                if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
            }
        }
        "5" {
            $newVal = -not $inst.retry_on_failure
            Show-SettingChange "Tekrar Deneme" $inst.retry_on_failure $newVal
            $ok = Read-Host "  Onay? [E/h]"
            if ($ok -notmatch "^[Hh]") {
                $settings.installation.retry_on_failure = $newVal
                if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
            }
        }
        "6" {
            $newCount = Read-Host ("  Tekrar sayisi [{0}]" -f $inst.retry_count)
            if ($newCount -match "^\d+$") {
                Show-SettingChange "Tekrar Sayisi" $inst.retry_count $newCount
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.installation.retry_count = [int]$newCount
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            }
        }
        "0" { return }
    }
    Read-Host "  Enter ile devam edin"
}

function Invoke-LogSettings {
    Show-SettingsHeader "Log Ayarlari"
    $settings = Read-SettingsJson
    if (-not $settings) { Write-Host "  [HATA] Ayar dosyasi okunamadi." -ForegroundColor Red; Read-Host "  Enter"; return }

    $log = $settings.logging
    Draw-Line -Color Cyan
    Write-Host ("  Log Seviyesi      : {0}" -f $log.log_level) -ForegroundColor White
    Write-Host ("  Maks Log Dosyasi  : {0}" -f $log.max_log_files) -ForegroundColor White
    Write-Host ("  Log Saklama (gun) : {0}" -f $log.log_retention_days) -ForegroundColor White
    Draw-Line -Color Cyan

    Write-Host "  [1] Log seviyesi  [2] Maks log dosyasi  [3] Saklama suresi  [0] Geri"
    $sub = Read-Host "  Seciminiz"

    switch ($sub) {
        "1" {
            Write-Host "  [1] DEBUG  [2] INFO  [3] WARNING  [4] ERROR" -ForegroundColor Cyan
            $s = Read-Host "  Yeni log seviyesi"
            $newLevel = switch ($s) { "1" { "DEBUG" } "2" { "INFO" } "3" { "WARNING" } "4" { "ERROR" } default { $null } }
            if ($newLevel) {
                Show-SettingChange "Log Seviyesi" $log.log_level $newLevel
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.logging.log_level = $newLevel
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            }
        }
        "2" {
            $newMax = Read-Host ("  Maks log dosyasi [{0}]" -f $log.max_log_files)
            if ($newMax -match "^\d+$" -and [int]$newMax -ge 1) {
                Show-SettingChange "Maks Log Dosyasi" $log.max_log_files $newMax
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.logging.max_log_files = [int]$newMax
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            } else { Write-Host "  Gecersiz deger." -ForegroundColor Yellow }
        }
        "3" {
            $newDays = Read-Host ("  Saklama suresi (gun) [{0}]" -f $log.log_retention_days)
            if ($newDays -match "^\d+$" -and [int]$newDays -ge 1) {
                Show-SettingChange "Log Saklama" $log.log_retention_days "$newDays gun"
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.logging.log_retention_days = [int]$newDays
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            } else { Write-Host "  Gecersiz deger." -ForegroundColor Yellow }
        }
        "0" { return }
    }
    Read-Host "  Enter ile devam edin"
}

function Invoke-BackupSettings {
    Show-SettingsHeader "Yedekleme Ayarlari"
    $settings = Read-SettingsJson
    if (-not $settings) { Write-Host "  [HATA] Ayar dosyasi okunamadi." -ForegroundColor Red; Read-Host "  Enter"; return }

    $bk = $settings.backup
    $defaultDir = Get-BackupDirPath
    $currentDir = if ($bk.backup_dir) { $bk.backup_dir } else { $defaultDir }

    Draw-Line -Color Cyan
    Write-Host ("  Yedek Klasoru       : {0}" -f $currentDir) -ForegroundColor White
    Write-Host ("  Otomatik Geri Yukle : {0}" -f $bk.auto_restore_point) -ForegroundColor White
    Draw-Line -Color Cyan

    Write-Host "  [1] Yedek klasorunu degistir  [2] Otomatik geri yuklemeyi aç/kapat  [0] Geri"
    $sub = Read-Host "  Seciminiz"

    switch ($sub) {
        "1" {
            $newDir = Read-Host ("  Yeni yedek klasoru yolu [{0}]" -f $currentDir)
            if (-not [string]::IsNullOrWhiteSpace($newDir)) {
                Show-SettingChange "Yedek Klasoru" $currentDir $newDir
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.backup.backup_dir = $newDir.Trim()
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            }
        }
        "2" {
            $newVal = -not $bk.auto_restore_point
            Show-SettingChange "Otomatik Geri Yukleme" $bk.auto_restore_point $newVal
            $ok = Read-Host "  Onay? [E/h]"
            if ($ok -notmatch "^[Hh]") {
                $settings.backup.auto_restore_point = $newVal
                if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
            }
        }
        "0" { return }
    }
    Read-Host "  Enter ile devam edin"
}

function Invoke-UiSettings {
    Show-SettingsHeader "UI Ayarlari"
    $settings = Read-SettingsJson
    if (-not $settings) { Write-Host "  [HATA] Ayar dosyasi okunamadi." -ForegroundColor Red; Read-Host "  Enter"; return }

    $ui = $settings.ui
    Draw-Line -Color Cyan
    Write-Host ("  Dil               : {0}" -f $ui.language) -ForegroundColor White
    Write-Host ("  Renk Temasi       : {0}" -f $ui.color_theme) -ForegroundColor White
    Write-Host ("  Kompakt Baslik    : {0}" -f $ui.compact_header) -ForegroundColor White
    Write-Host ("  Admin Uyarisi     : {0}" -f $ui.show_admin_warning) -ForegroundColor White
    Draw-Line -Color Cyan

    Write-Host "  [1] Dil  [2] Tema  [3] Kompakt baslik  [4] Admin uyarisi  [0] Geri"
    $sub = Read-Host "  Seciminiz"

    switch ($sub) {
        "1" {
            Write-Host "  [1] tr-TR  [2] en-US" -ForegroundColor Cyan
            $s = Read-Host "  Dil secin"
            $newLang = switch ($s) { "1" { "tr-TR" } "2" { "en-US" } default { $null } }
            if ($newLang) {
                Show-SettingChange "Dil" $ui.language $newLang
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.ui.language = $newLang
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            }
        }
        "2" {
            Write-Host "  [1] default  [2] dark  [3] light" -ForegroundColor Cyan
            $s = Read-Host "  Tema secin"
            $newTheme = switch ($s) { "1" { "default" } "2" { "dark" } "3" { "light" } default { $null } }
            if ($newTheme) {
                Show-SettingChange "Renk Temasi" $ui.color_theme $newTheme
                $ok = Read-Host "  Onay? [E/h]"
                if ($ok -notmatch "^[Hh]") {
                    $settings.ui.color_theme = $newTheme
                    if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
                }
            }
        }
        "3" {
            $newVal = -not $ui.compact_header
            Show-SettingChange "Kompakt Baslik" $ui.compact_header $newVal
            $ok = Read-Host "  Onay? [E/h]"
            if ($ok -notmatch "^[Hh]") {
                $settings.ui.compact_header = $newVal
                if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
            }
        }
        "4" {
            $newVal = -not $ui.show_admin_warning
            Show-SettingChange "Admin Uyarisi" $ui.show_admin_warning $newVal
            $ok = Read-Host "  Onay? [E/h]"
            if ($ok -notmatch "^[Hh]") {
                $settings.ui.show_admin_warning = $newVal
                if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
            }
        }
        "0" { return }
    }
    Read-Host "  Enter ile devam edin"
}

function Invoke-WingetPathSetting {
    Show-SettingsHeader "WinGet Yolu Ayarla"
    $settings = Read-SettingsJson
    if (-not $settings) { Write-Host "  [HATA] Ayar dosyasi okunamadi." -ForegroundColor Red; Read-Host "  Enter"; return }

    $currentPath = $settings.installation.winget_path
    Draw-Line -Color Cyan
    Write-Host ("  Mevcut WinGet Yolu : {0}" -f $(if ($currentPath) { $currentPath } else { "(otomatik)" })) -ForegroundColor White
    Draw-Line -Color Cyan
    Write-Host "  Bos bırakırsanız WinGet otomatik bulunur." -ForegroundColor Gray

    $newPath = Read-Host "  Yeni WinGet yolu (bos=otomatik, 0=iptal)"
    if ($newPath.Trim() -eq "0") { return }

    $finalPath = $newPath.Trim()
    if ($finalPath -and -not (Test-Path $finalPath)) {
        Write-Host ("  [UYARI] Bu yolda dosya bulunamadi: {0}" -f $finalPath) -ForegroundColor Yellow
        $cont = Read-Host "  Yine de kaydetmek istiyor musunuz? [E/h]"
        if ($cont -match "^[Hh]") { return }
    }

    Show-SettingChange "WinGet Yolu" $(if ($currentPath) { $currentPath } else { "(otomatik)" }) $(if ($finalPath) { $finalPath } else { "(otomatik)" })
    $ok = Read-Host "  Onay? [E/h]"
    if ($ok -notmatch "^[Hh]") {
        $settings.installation.winget_path = $finalPath
        if (Write-SettingsJson -Data $settings) { Write-Host "  [OK] Guncellendi." -ForegroundColor Green }
    }
    Read-Host "  Enter ile devam edin"
}

function Invoke-ShowAllSettings {
    Show-SettingsHeader "Tum Ayarlar"
    $settings = Read-SettingsJson
    if (-not $settings) { Write-Host "  [HATA] Ayar dosyasi okunamadi." -ForegroundColor Red; Read-Host "  Enter"; return }

    Draw-Line -Color Cyan -Char "─"
    Write-Host "  [KURULUM AYARLARI]" -ForegroundColor Cyan
    Write-Host ("    Scope           : {0}" -f $settings.installation.default_install_scope) -ForegroundColor White
    Write-Host ("    Mimari          : {0}" -f $settings.installation.default_architecture) -ForegroundColor White
    Write-Host ("    Sessiz Kurulum  : {0}" -f $settings.installation.silent_install) -ForegroundColor White
    Write-Host ("    Dogrulama       : {0}" -f $settings.installation.verify_after_install) -ForegroundColor White
    Write-Host ("    Tekrar Dene     : {0} (max {1})" -f $settings.installation.retry_on_failure, $settings.installation.retry_count) -ForegroundColor White
    Write-Host ("    WinGet Yolu     : {0}" -f $(if ($settings.installation.winget_path) { $settings.installation.winget_path } else { "(otomatik)" })) -ForegroundColor White

    Draw-Line -Color Cyan -Char "─"
    Write-Host "  [LOG AYARLARI]" -ForegroundColor Cyan
    Write-Host ("    Log Seviyesi    : {0}" -f $settings.logging.log_level) -ForegroundColor White
    Write-Host ("    Maks Dosya      : {0}" -f $settings.logging.max_log_files) -ForegroundColor White
    Write-Host ("    Saklama Suresi  : {0} gun" -f $settings.logging.log_retention_days) -ForegroundColor White

    Draw-Line -Color Cyan -Char "─"
    Write-Host "  [YEDEKLEME AYARLARI]" -ForegroundColor Cyan
    Write-Host ("    Yedek Klasoru   : {0}" -f $(if ($settings.backup.backup_dir) { $settings.backup.backup_dir } else { "(varsayilan)" })) -ForegroundColor White
    Write-Host ("    Otomatik Geri   : {0}" -f $settings.backup.auto_restore_point) -ForegroundColor White

    Draw-Line -Color Cyan -Char "─"
    Write-Host "  [UI AYARLARI]" -ForegroundColor Cyan
    Write-Host ("    Dil             : {0}" -f $settings.ui.language) -ForegroundColor White
    Write-Host ("    Tema            : {0}" -f $settings.ui.color_theme) -ForegroundColor White
    Write-Host ("    Kompakt Baslik  : {0}" -f $settings.ui.compact_header) -ForegroundColor White
    Write-Host ("    Admin Uyarisi   : {0}" -f $settings.ui.show_admin_warning) -ForegroundColor White
    Draw-Line -Color Cyan -Char "─"

    Read-Host "  Enter ile devam edin"
}

function Invoke-ResetToDefaults {
    Show-SettingsHeader "Fabrika Ayarlarina Sifirla"
    Draw-Line -Color Red -Char "!"
    Write-Host "  UYARI: Tum ayarlar fabrika degerlerine sifirlanacak!" -ForegroundColor Red
    Write-Host "  Bu islem geri alinamaz." -ForegroundColor Red
    Draw-Line -Color Red -Char "!"

    $ok1 = Read-Host "  Emin misiniz? [E/h]"
    if ($ok1 -notmatch "^[Ee]") { Write-Host "  Iptal edildi." -ForegroundColor Yellow; Read-Host "  Enter"; return }

    $ok2 = Read-Host "  Onaylamak icin 'SIFIRLA' yazin"
    if ($ok2 -ne "SIFIRLA") { Write-Host "  Eslesmedi. Iptal edildi." -ForegroundColor Yellow; Read-Host "  Enter"; return }

    # Mevcut ayarları yedekle
    $settingsPath = Get-SettingsFilePath
    if (Test-Path $settingsPath) {
        $backupPath = New-ProfileBackup -SourcePath $settingsPath -Prefix "settings"
        if ($backupPath) { Write-Host ("  [i] Onceki ayarlar yedeklendi: {0}" -f $backupPath) -ForegroundColor DarkCyan }
    }

    $defaults = [PSCustomObject]@{
        version      = "1.0.0"
        last_updated = (Get-Date -Format "yyyy-MM-dd")
        ui           = [PSCustomObject]@{
            language           = "tr-TR"
            color_theme        = "default"
            compact_header     = $true
            show_admin_warning = $true
        }
        installation = [PSCustomObject]@{
            default_install_scope  = "user"
            default_architecture   = "x64"
            silent_install         = $true
            verify_after_install   = $true
            retry_on_failure       = $true
            retry_count            = 3
            winget_path            = ""
        }
        logging      = [PSCustomObject]@{
            log_level          = "INFO"
            max_log_files      = 20
            log_retention_days = 14
        }
        backup       = [PSCustomObject]@{
            backup_dir          = ""
            auto_restore_point  = $false
        }
        updates      = [PSCustomObject]@{
            check_on_startup = $false
            auto_update      = $false
        }
    }

    if (Write-SettingsJson -Data $defaults) {
        Write-Host "  [OK] Ayarlar fabrika degerlerine sifirlandı." -ForegroundColor Green
    }
    Read-Host "  Enter ile devam edin"
}

function Invoke-SettingsManagement {
    while ($true) {
        Show-SettingsHeader "Kurulum Ayarlari Yonetimi"
        Write-Host "  [1] Kurulum Ayarlari (Scope, Arch, Silent, Verify, Retry)" -ForegroundColor White
        Write-Host "  [2] Log Ayarlari (log_level, max_log_files, log_retention_days)" -ForegroundColor White
        Write-Host "  [3] Yedekleme Ayarlari (backup_dir, auto_restore_point)" -ForegroundColor White
        Write-Host "  [4] UI Ayarlari (language, color_theme, compact_header, show_admin_warning)" -ForegroundColor White
        Write-Host "  [5] WinGet Yolu Ayarla" -ForegroundColor White
        Write-Host "  [6] Tum Ayarlari Goruntule" -ForegroundColor White
        Write-Host "  [7] Fabrika Ayarlarina Sifirla" -ForegroundColor White
        Draw-Line -Color DarkCyan
        Write-Host "  [0] Geri" -ForegroundColor Gray

        $choice = Read-Host "  Seciminiz"
        switch ($choice) {
            "1" { Invoke-InstallSettings }
            "2" { Invoke-LogSettings }
            "3" { Invoke-BackupSettings }
            "4" { Invoke-UiSettings }
            "5" { Invoke-WingetPathSetting }
            "6" { Invoke-ShowAllSettings }
            "7" { Invoke-ResetToDefaults }
            "0" { return }
            default { Write-Host "  Gecersiz secim." -ForegroundColor Yellow; Start-Sleep -Milliseconds 600 }
        }
    }
}

#endregion

#region ─── YEDEKLEME VE GERİ YÜKLEME: Invoke-BackupManagement ───────────────

function Get-BackupList {
    param([string]$Filter = "")
    $backupDir = Get-BackupDirPath
    if (-not (Test-Path $backupDir)) { return @() }
    $pattern = if ($Filter) { "*${Filter}*" } else { "*.json" }
    return @(Get-ChildItem -Path $backupDir -Filter $pattern -File |
             Sort-Object LastWriteTime -Descending)
}

function Show-BackupListTable {
    param([System.IO.FileInfo[]]$Backups)
    if ($Backups.Count -eq 0) {
        Write-Host "  Hic yedek bulunamadi." -ForegroundColor Yellow
        return
    }
    Draw-Line -Color DarkCyan
    Write-Host ("  {0,-4} {1,-40} {2,-20} {3}" -f "No", "Dosya Adı", "Tarih", "Boyut") -ForegroundColor White
    Draw-Line -Color DarkCyan
    for ($i = 0; $i -lt $Backups.Count; $i++) {
        $f = $Backups[$i]
        $size = if ($f.Length -gt 1024) { "{0} KB" -f [math]::Round($f.Length/1024,1) } else { "$($f.Length) B" }
        Write-Host ("  [{0,-2}] {1,-40} {2,-20} {3}" -f ($i+1), $f.Name, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), $size) -ForegroundColor DarkCyan
    }
    Draw-Line -Color DarkCyan
}

function Invoke-CreateBackupFor {
    param([string]$SourcePath, [string]$Prefix, [string]$Label)
    if (-not (Test-Path $SourcePath)) {
        Write-Host ("  [HATA] Kaynak dosya bulunamadi: {0}" -f $SourcePath) -ForegroundColor Red
        return
    }
    $backupPath = New-ProfileBackup -SourcePath $SourcePath -Prefix $Prefix
    if ($backupPath) {
        Write-Host ("  [OK] {0} yedeği olusturuldu:" -f $Label) -ForegroundColor Green
        Write-Host ("       {0}" -f $backupPath) -ForegroundColor DarkCyan
    } else {
        Write-Host ("  [HATA] {0} yedeği olusturulamadi." -f $Label) -ForegroundColor Red
    }
}

function Invoke-BackupManagement {
    while ($true) {
        Show-BackupHeader "Yedekleme ve Geri Yukleme"
        Write-Host "  [1] Katalog Yedegi Olustur (apps.json)" -ForegroundColor White
        Write-Host "  [2] Profil Yedegi Olustur (profiles.json)" -ForegroundColor White
        Write-Host "  [3] Ayar Yedegi Olustur (settings.json)" -ForegroundColor White
        Write-Host "  [4] Tumunu Yedekle" -ForegroundColor White
        Write-Host "  [5] Yedekleri Listele" -ForegroundColor White
        Write-Host "  [6] Yedekten Geri Yukle" -ForegroundColor White
        Write-Host "  [7] Yedegi Sil" -ForegroundColor White
        Draw-Line -Color DarkCyan
        Write-Host "  [0] Geri" -ForegroundColor Gray

        $choice = Read-Host "  Seciminiz"
        switch ($choice) {
            "1" {
                Invoke-CreateBackupFor -SourcePath (Get-AppsFilePath) -Prefix "apps" -Label "Katalog"
                Read-Host "  Enter ile devam"
            }
            "2" {
                Invoke-CreateBackupFor -SourcePath (Get-ProfilesFilePath) -Prefix "profiles" -Label "Profil"
                Read-Host "  Enter ile devam"
            }
            "3" {
                Invoke-CreateBackupFor -SourcePath (Get-SettingsFilePath) -Prefix "settings" -Label "Ayar"
                Read-Host "  Enter ile devam"
            }
            "4" {
                Show-BackupHeader "Tum Dosyalar Yedekleniyor"
                Invoke-CreateBackupFor -SourcePath (Get-AppsFilePath)      -Prefix "apps"     -Label "Katalog"
                Invoke-CreateBackupFor -SourcePath (Get-ProfilesFilePath)  -Prefix "profiles" -Label "Profil"
                Invoke-CreateBackupFor -SourcePath (Get-SettingsFilePath)  -Prefix "settings" -Label "Ayar"
                Write-Host ""
                Write-Host "  [OK] Tum yedekler tamamlandi." -ForegroundColor Green
                Read-Host "  Enter ile devam"
            }
            "5" {
                Show-BackupHeader "Yedek Listesi"
                Write-Host "  [1] Tum Yedekler  [2] Katalog  [3] Profil  [4] Ayar" -ForegroundColor Gray
                $filter = Read-Host "  Filtre"
                $filterStr = switch ($filter) { "2" { "apps" } "3" { "profiles" } "4" { "settings" } default { "" } }
                $backups = Get-BackupList -Filter $filterStr
                Show-BackupListTable -Backups $backups
                Read-Host "  Enter ile devam"
            }
            "6" {
                Show-BackupHeader "Yedekten Geri Yukle"
                Write-Host "  Kaynak sec:" -ForegroundColor Gray
                Write-Host "  [1] Katalog (apps.json)  [2] Profil (profiles.json)  [3] Ayar (settings.json)  [0] Geri"
                $src = Read-Host "  Seciminiz"
                if ($src -eq "0") { continue }

                $sourceInfo = switch ($src) {
                    "1" { @{ Path = Get-AppsFilePath;     Prefix = "apps";     Label = "Katalog" } }
                    "2" { @{ Path = Get-ProfilesFilePath; Prefix = "profiles"; Label = "Profil"  } }
                    "3" { @{ Path = Get-SettingsFilePath; Prefix = "settings"; Label = "Ayar"    } }
                    default { $null }
                }
                if (-not $sourceInfo) { Write-Host "  Gecersiz secim." -ForegroundColor Yellow; continue }

                $backups = Get-BackupList -Filter $sourceInfo.Prefix
                if ($backups.Count -eq 0) {
                    Write-Host ("  {0} icin hic yedek bulunamadi." -f $sourceInfo.Label) -ForegroundColor Yellow
                    Read-Host "  Enter"; continue
                }

                Show-BackupListTable -Backups $backups
                $bChoice = Read-Host "  Geri yuklenecek yedek numarasi (0=iptal)"
                if ($bChoice -eq "0") { continue }
                if ($bChoice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; continue }
                $bIdx = [int]$bChoice - 1
                if ($bIdx -lt 0 -or $bIdx -ge $backups.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; continue }

                $selectedBackup = $backups[$bIdx]
                Draw-Line -Color Yellow -Char "!"
                Write-Host ("  Geri yuklenecek: {0}" -f $selectedBackup.Name) -ForegroundColor Yellow
                Write-Host ("  Hedef dosya    : {0}" -f $sourceInfo.Path) -ForegroundColor Yellow
                Write-Host "  Mevcut dosya, geri yuklemeden once otomatik yedeklenecek." -ForegroundColor Gray
                Draw-Line -Color Yellow -Char "!"

                $ok = Read-Host "  Onayliyor musunuz? [E/h]"
                if ($ok -match "^[Hh]") { Write-Host "  Iptal edildi." -ForegroundColor Yellow; continue }

                # Mevcut dosyayı yedekle
                if (Test-Path $sourceInfo.Path) {
                    $safeguard = New-ProfileBackup -SourcePath $sourceInfo.Path -Prefix ($sourceInfo.Prefix + "_onceki")
                    if ($safeguard) { Write-Host ("  [i] Mevcut dosya yedeklendi: {0}" -f $safeguard) -ForegroundColor DarkCyan }
                }

                try {
                    Copy-Item -Path $selectedBackup.FullName -Destination $sourceInfo.Path -Force -ErrorAction Stop
                    Write-Host ("  [OK] Geri yukleme tamamlandi: {0}" -f $sourceInfo.Label) -ForegroundColor Green
                } catch {
                    Write-Host ("  [HATA] Geri yukleme basarisiz: {0}" -f $_) -ForegroundColor Red
                }
                Read-Host "  Enter ile devam"
            }
            "7" {
                Show-BackupHeader "Yedek Sil"
                $backups = Get-BackupList
                if ($backups.Count -eq 0) {
                    Write-Host "  Hic yedek yok." -ForegroundColor Yellow
                    Read-Host "  Enter"; continue
                }
                Show-BackupListTable -Backups $backups
                $dChoice = Read-Host "  Silinecek yedek numarasi (0=iptal)"
                if ($dChoice -eq "0") { continue }
                if ($dChoice -notmatch "^\d+$") { Write-Host "  Gecersiz giris." -ForegroundColor Yellow; continue }
                $dIdx = [int]$dChoice - 1
                if ($dIdx -lt 0 -or $dIdx -ge $backups.Count) { Write-Host "  Gecersiz numara." -ForegroundColor Yellow; continue }

                $toDelete = $backups[$dIdx]
                Write-Host ("  Silinecek: {0}" -f $toDelete.Name) -ForegroundColor Yellow
                $ok = Read-Host "  Onayliyor musunuz? [E/h]"
                if ($ok -match "^[Hh]") { Write-Host "  Iptal edildi." -ForegroundColor Yellow; continue }

                try {
                    Remove-Item -Path $toDelete.FullName -Force -ErrorAction Stop
                    Write-Host ("  [OK] Yedek silindi: {0}" -f $toDelete.Name) -ForegroundColor Green
                } catch {
                    Write-Host ("  [HATA] Silinemedi: {0}" -f $_) -ForegroundColor Red
                }
                Read-Host "  Enter ile devam"
            }
            "0" { return }
            default { Write-Host "  Gecersiz secim." -ForegroundColor Yellow; Start-Sleep -Milliseconds 600 }
        }
    }
}

#endregion

#region ─── MODULE EXPORT ─────────────────────────────────────────────────────

Export-ModuleMember -Function @(
    'Invoke-ProfileManagement',
    'Invoke-SettingsManagement',
    'Invoke-BackupManagement',
    # Yardımcı (dahili kullanım için de erişilebilir)
    'Get-ProfilesFilePath',
    'Get-AppsFilePath',
    'Get-SettingsFilePath',
    'Get-BackupDirPath',
    'Read-ProfilesJson',
    'Write-ProfilesJson',
    'Read-AppsJson',
    'Read-SettingsJson',
    'Write-SettingsJson',
    'New-ProfileBackup',
    'Get-BackupList',
    'Show-ProfileList',
    'Select-ApplicationsFromCatalog',
    'Invoke-ReorderProfileApps',
    'Invoke-InstallProfile'
)

#endregion
