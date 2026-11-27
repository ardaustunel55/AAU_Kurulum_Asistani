# ============================================================================
# AAU KURULUM ASISTANI - FORMAT SONRASI SIHIRBAZ VE DEBLOAT / INCE AYAR MODULU
# ============================================================================

function Test-PostFormatAdmin {
    try {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Invoke-DebloatTelemetryAndAds {
    Write-Host "`n  [TELEMETRI & REKLAM KAPATMA]" -ForegroundColor Cyan
    if (-not (Test-PostFormatAdmin)) {
        Write-Host "  [UYARI] Sistem geneli ayarlar icin yonetici yetkisi gerekir." -ForegroundColor Yellow
        return
    }
    try {
        # 1. Telemetri en dusuk duzey (0/1)
        $dcPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $dcPath)) { New-Item -Path $dcPath -Force | Out-Null }
        Set-ItemProperty -Path $dcPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force

        # 2. Reklam Kimligi (Advertising ID) kapat
        $adPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
        if (-not (Test-Path $adPath)) { New-Item -Path $adPath -Force | Out-Null }
        Set-ItemProperty -Path $adPath -Name "Enabled" -Value 0 -Type DWord -Force

        # 3. Baslat Menusu ve Kilit Ekrani onerileri/reklamlari kapat
        $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (-not (Test-Path $cdmPath)) { New-Item -Path $cdmPath -Force | Out-Null }
        foreach ($name in @("SubscribedContent-338388Enabled","SubscribedContent-338389Enabled","SubscribedContent-338393Enabled","SubscribedContent-353694Enabled","SubscribedContent-353696Enabled","SystemPaneSuggestionsEnabled","SoftLandingEnabled","RotatingLockScreenOverlayEnabled")) {
            Set-ItemProperty -Path $cdmPath -Name $name -Value 0 -Type DWord -Force
        }

        Write-Host "  [BASARILI] Telemetri, reklam kimligi ve sistem onerileri kapatildi." -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) { Write-LogSuccess "Debloat: Telemetri ve reklam ayarlari kapatildi." }
    } catch {
        Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-DisableCopilotWidgetsEdgeBg {
    Write-Host "`n  [COPILOT, WIDGETS & EDGE ARKA PLAN]" -ForegroundColor Cyan
    if (-not (Test-PostFormatAdmin)) {
        Write-Host "  [UYARI] Bu islem icin yonetici yetkisi gerekir." -ForegroundColor Yellow
        return
    }
    try {
        # Copilot kapat
        $cpPath = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
        if (-not (Test-Path $cpPath)) { New-Item -Path $cpPath -Force | Out-Null }
        Set-ItemProperty -Path $cpPath -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force

        # Widgets / Haberler ve Ilgi Alanlari kapat
        $wdPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
        if (-not (Test-Path $wdPath)) { New-Item -Path $wdPath -Force | Out-Null }
        Set-ItemProperty -Path $wdPath -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force

        # Edge arka plan calismasi & ilk calistirma kapat
        $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (-not (Test-Path $edgePath)) { New-Item -Path $edgePath -Force | Out-Null }
        Set-ItemProperty -Path $edgePath -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $edgePath -Name "StartupBoostEnabled" -Value 0 -Type DWord -Force

        Write-Host "  [BASARILI] Copilot, Widgets ve Edge arka plan calismasi devre disi birakildi." -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) { Write-LogSuccess "Debloat: Copilot, Widgets ve Edge arka plan kapatildi." }
    } catch {
        Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-DisableForcedUpdateReboot {
    Write-Host "`n  [WINDOWS UPDATE ZORUNLU YENIDEN BASLATMA]" -ForegroundColor Cyan
    if (-not (Test-PostFormatAdmin)) {
        Write-Host "  [UYARI] Yonetici yetkisi gerekir." -ForegroundColor Yellow
        return
    }
    try {
        $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        if (-not (Test-Path $auPath)) { New-Item -Path $auPath -Force | Out-Null }
        Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
        Write-Host "  [BASARILI] Oturum acikken Windows Update zorunlu yeniden baslatmasi engellendi." -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) { Write-LogSuccess "Windows Update zorunlu yeniden baslatma engellendi." }
    } catch {
        Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-RemoveBloatwareApps {
    Write-Host "`n  [GEREKSIZ UWP / BLOATWARE UYGULAMALARI]" -ForegroundColor Cyan
    $bloatTargets = @(
        @{ Pattern = "*Clipchamp*"; Label = "Clipchamp" },
        @{ Pattern = "*BingNews*"; Label = "Microsoft Haberler" },
        @{ Pattern = "*BingWeather*"; Label = "Hava Durumu" },
        @{ Pattern = "*MicrosoftSolitaireCollection*"; Label = "Solitaire Collection" },
        @{ Pattern = "*WindowsMaps*"; Label = "Haritalar" },
        @{ Pattern = "*ZuneVideo*"; Label = "Filmler ve TV" },
        @{ Pattern = "*YourPhone*"; Label = "Telefon Baglantisi" },
        @{ Pattern = "*GetHelp*"; Label = "Yardim Al" },
        @{ Pattern = "*PowerAutomateDesktop*"; Label = "Power Automate" },
        @{ Pattern = "*OutlookForWindows*"; Label = "Yeni Outlook (UWP)" }
    )

    $found = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($bt in $bloatTargets) {
        $pkg = Get-AppxPackage -Name $bt.Pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) {
            $found.Add([PSCustomObject]@{ Label = $bt.Label; Name = $pkg.Name; FullName = $pkg.PackageFullName })
        }
    }

    if ($found.Count -eq 0) {
        Write-Host "  [TEBRIKLER] Kaldirilabilecek gereksiz bloatware paketi bulunamadi!" -ForegroundColor Green
        return
    }

    Write-Host "  Bulunan $($found.Count) bloatware paketi:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $found.Count; $i++) {
        Write-Host ("  [{0,2}] {1} ({2})" -f ($i + 1), $found[$i].Label, $found[$i].Name) -ForegroundColor White
    }
    Write-Host ""
    $pick = Read-Host "  Kaldirilacak numaralar (T=Tumu | Orn: 1,3 | 0=Iptal)"
    if (-not $pick -or $pick.Trim() -eq "0") { Write-Host "  [BILGI] Iptal edildi." -ForegroundColor Yellow; return }

    $toRemove = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($pick.Trim().ToUpper() -eq "T") {
        foreach ($f in $found) { $toRemove.Add($f) }
    } else {
        foreach ($tok in ($pick -split '[,\s]+')) {
            if ($tok -match '^\d+$') {
                $idx = [int]$tok
                if ($idx -ge 1 -and $idx -le $found.Count) { $toRemove.Add($found[$idx - 1]) }
            }
        }
    }

    foreach ($item in $toRemove) {
        Write-Host "  Kaldiriliyor: $($item.Label)..." -ForegroundColor Yellow
        try {
            Remove-AppxPackage -Package $item.FullName -ErrorAction Stop
            Write-Host "  [BASARILI] $($item.Label) kaldirildi." -ForegroundColor Green
            if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) { Write-LogSuccess "Bloatware kaldirildi: $($item.Name)" }
        } catch {
            Write-Host "  [HATA] $($item.Label): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Show-DebloatPrivacyMenu {
    $items = @(
        "Gereksiz UWP / Bloatware Uygulamalarini Kaldir",
        "Telemetri, Reklam Kimligi ve Onerileri Kapat",
        "Copilot, Widgets ve Edge Arka Planini Kapat",
        "Windows Update Zorunlu Yeniden Baslatmayi Kapat",
        "Tum Gizlilik ve Debloat Ayarlarini Tek Tikla Uygula"
    )
    while ($true) {
        if (Get-Command "Show-ScreenTransition" -ErrorAction SilentlyContinue) { Show-ScreenTransition }
        if (Get-Command "Show-AppHeader" -ErrorAction SilentlyContinue) { Show-AppHeader }
        Write-Host ""
        Write-Host "  [22] | Windows Debloat & Gizlilik Merkezi" -ForegroundColor Yellow
        if (Get-Command "Draw-HorizontalLine" -ErrorAction SilentlyContinue) { Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-" }
        Write-Host ""
        for ($i = 0; $i -lt $items.Count; $i++) {
            Write-Host ("  [{0,2}] | {1}" -f ($i + 1), $items[$i]) -ForegroundColor Cyan
        }
        Write-Host ""
        Write-Host "  [ 0] | Ana Menuye Don  [ESC]" -ForegroundColor Red
        Write-Host ""
        $inp = if (Get-Command "Read-MenuInput" -ErrorAction SilentlyContinue) { Read-MenuInput } else { Read-Host "  Seciminiz" }
        $ch = if ($null -ne $inp) { $inp.Trim() } else { "" }
        if ($ch -eq "ESC" -or $ch -eq "0" -or $ch -eq "00") { return }
        switch ($ch) {
            "1" { Invoke-RemoveBloatwareApps }
            "2" { Invoke-DebloatTelemetryAndAds }
            "3" { Invoke-DisableCopilotWidgetsEdgeBg }
            "4" { Invoke-DisableForcedUpdateReboot }
            "5" {
                Invoke-DebloatTelemetryAndAds
                Invoke-DisableCopilotWidgetsEdgeBg
                Invoke-DisableForcedUpdateReboot
            }
            default { Write-Host "  [HATA] Gecersiz secim." -ForegroundColor Red; Start-Sleep -Seconds 1; continue }
        }
        if (Get-Command "Wait-UserKeyPress" -ErrorAction SilentlyContinue) { Wait-UserKeyPress -PromptMessage "Debloat menusune donmek icin bir tusa basin..." }
    }
}

function Toggle-DesktopSystemIcons {
    Write-Host "`n  [MASAUSTU SISTEM IKONLARI]" -ForegroundColor Green
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        $guids = @(
            "{20D04FE0-3AEA-1069-A2D8-08002B30309D}", # Bu Bilgisayar
            "{59031a47-3f72-44a7-89c5-5595fe6b30ee}", # Kullanici Dosyalari
            "{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}", # Ag
            "{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}"  # Denetim Masasi
        )
        $cur = (Get-ItemProperty -Path $regPath -Name $guids[0] -ErrorAction SilentlyContinue).($guids[0])
        $newVal = if ($cur -eq 0) { 1 } else { 0 }
        foreach ($g in $guids) { Set-ItemProperty -Path $regPath -Name $g -Value $newVal -Type DWord -Force }
        $st = if ($newVal -eq 0) { "GOSTERILIYOR" } else { "GIZLI" }
        Write-Host "  [BASARILI] Masaustu sistem ikonlari (Bu Bilgisayar, Belgeler, Ag, Denetim Masasi): $st" -ForegroundColor Green
    } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
}

function Toggle-ExplorerLaunchToThisPC {
    Write-Host "`n  [DOSYA GEZGINI ACILIS KONUMU]" -ForegroundColor Green
    try {
        $expPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $cur = (Get-ItemProperty -Path $expPath -Name "LaunchTo" -ErrorAction SilentlyContinue).LaunchTo
        $newVal = if ($cur -eq 1) { 2 } else { 1 }
        Set-ItemProperty -Path $expPath -Name "LaunchTo" -Value $newVal -Type DWord -Force
        $st = if ($newVal -eq 1) { "BU BILGISAYAR" } else { "HIZLI ERISIM / ANA SAYFA" }
        Write-Host "  [BASARILI] Dosya Gezgini acilisi: $st" -ForegroundColor Green
    } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
}

function Invoke-UltimatePerformancePlan {
    Write-Host "`n  [NIHAI PERFORMANS GUC PLANI]" -ForegroundColor Cyan
    if (-not (Test-PostFormatAdmin)) {
        Write-Host "  [UYARI] Yonetici yetkisi gerekir." -ForegroundColor Yellow
        return
    }
    try {
        $out = & powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
        if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
            $guid = $matches[1]
            & powercfg /setactive $guid
            Write-Host "  [BASARILI] Nihai Performans (Ultimate Performance) guc plani aktif edildi! ($guid)" -ForegroundColor Green
        } else {
            & powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
            Write-Host "  [BASARILI] Yuksek Performans guc plani aktif edildi." -ForegroundColor Green
        }
    } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
}

function Toggle-HibernationMode {
    Write-Host "`n  [HAZIRDA BEKLET (HIBERNATION / hiberfil.sys)]" -ForegroundColor Cyan
    if (-not (Test-PostFormatAdmin)) {
        Write-Host "  [UYARI] Yonetici yetkisi gerekir." -ForegroundColor Yellow
        return
    }
    $hibFile = "$env:SystemDrive\hiberfil.sys"
    $exists = Test-Path -LiteralPath $hibFile -Force -ErrorAction SilentlyContinue
    Write-Host "  Mevcut durum: $(if ($exists) { 'ACIK (Diskte yer kapliyor)' } else { 'KAPALI' })" -ForegroundColor Yellow
    $ans = Read-Host "  $(if ($exists) { 'Kapatilsin mi (SSD/Disk alani acar)?' } else { 'Acilsin mi?' }) (E/H)"
    if ($ans -and $ans.Trim().ToUpper() -eq "E") {
        if ($exists) { & powercfg /h off; Write-Host "  [BASARILI] Hibernation kapatildi." -ForegroundColor Green }
        else { & powercfg /h on; Write-Host "  [BASARILI] Hibernation acildi." -ForegroundColor Green }
    }
}

function Invoke-GamingPerformanceTweaks {
    Write-Host "`n  [OYUN PERFORMANS INCE AYARLARI (GameDVR & HAGS)]" -ForegroundColor Cyan
    try {
        # GameDVR kapat
        $dvrPath = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $dvrPath)) { New-Item -Path $dvrPath -Force | Out-Null }
        Set-ItemProperty -Path $dvrPath -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
        # Fare ivmesini (Enhance Pointer Precision) kapat
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Force
        if (Test-PostFormatAdmin) {
            $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
            if (Test-Path $gfxPath) { Set-ItemProperty -Path $gfxPath -Name "HwSchMode" -Value 2 -Type DWord -Force }
        }
        Write-Host "  [BASARILI] GameDVR kapatildi, fare ivmesi kapatildi ve HAGS etkinlestirildi." -ForegroundColor Green
    } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
}

function Invoke-GpuAutoDetectDriver {
    Write-Host "`n  [EKRAN KARTI OTOMATIK TESPITI]" -ForegroundColor Cyan
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop)
        foreach ($g in $gpus) {
            Write-Host "  GPU: $($g.Name) (Surucu: $($g.DriverVersion))" -ForegroundColor White
            $n = "$($g.Name)".ToUpper()
            $url = if ($n -match 'NVIDIA') { "https://www.nvidia.com/Download/index.aspx" }
                   elseif ($n -match 'AMD|RADEON') { "https://www.amd.com/en/support/download/drivers.html" }
                   elseif ($n -match 'INTEL') { "https://www.intel.com/content/www/us/en/download-center/home.html" }
                   else { "" }
            if ($url) {
                Write-Host "  Surucu sayfasi: $url" -ForegroundColor DarkCyan
                $ans = Read-Host "  Tarayicida acilsin mi? (E/H)"
                if ($ans -and $ans.Trim().ToUpper() -eq "E") { Start-Process $url }
            }
        }
    } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
}

function Invoke-WifiProfileBackupRestore {
    Write-Host "`n  [WI-FI AGLARI VE SIFRELERI YEDEKLEME]" -ForegroundColor Cyan
    $wifiDir = Join-Path $PSScriptRoot "..\..\data\backups\wifi"
    if (-not (Test-Path $wifiDir)) { New-Item -Path $wifiDir -ItemType Directory -Force | Out-Null }
    Write-Host "  [1] Tum Wi-Fi Profillerini & Sifrelerini Disa Aktar (Export)" -ForegroundColor White
    Write-Host "  [2] Yedeklenen Wi-Fi Profillerini Geri Yukle (Import)" -ForegroundColor White
    $ch = Read-Host "  Seciminiz (1/2 | 0=Iptal)"
    if ($ch -eq "1") {
        & netsh wlan export profile key=clear folder="$wifiDir" | Out-Null
        $cnt = (Get-ChildItem -Path $wifiDir -Filter "*.xml" -ErrorAction SilentlyContinue).Count
        Write-Host "  [BASARILI] $cnt adet Wi-Fi profili yedeklendi: $wifiDir" -ForegroundColor Green
    } elseif ($ch -eq "2") {
        $xmls = @(Get-ChildItem -Path $wifiDir -Filter "*.xml" -ErrorAction SilentlyContinue)
        if ($xmls.Count -eq 0) { Write-Host "  [BILGI] Yedek klasorunde Wi-Fi XML dosyasi yok." -ForegroundColor Yellow; return }
        foreach ($x in $xmls) { & netsh wlan add profile filename="$($x.FullName)" user=all | Out-Null }
        Write-Host "  [BASARILI] $($xmls.Count) adet Wi-Fi profili geri yuklendi." -ForegroundColor Green
    }
}

function Invoke-DefenderExclusionManager {
    Write-Host "`n  [DEFENDER KLASOR DISLAMA (EXCLUSION)]" -ForegroundColor Cyan
    if (-not (Test-PostFormatAdmin)) {
        Write-Host "  [UYARI] Yonetici yetkisi gerekir." -ForegroundColor Yellow
        return
    }
    try {
        $prefs = Get-MpPreference -ErrorAction Stop
        Write-Host "  Mevcut dislanan klasorler:" -ForegroundColor DarkCyan
        if ($prefs.ExclusionPath) { $prefs.ExclusionPath | ForEach-Object { Write-Host "    - $_" -ForegroundColor White } }
        else { Write-Host "    (Yok)" -ForegroundColor DarkGray }
        Write-Host ""
        $newPath = Read-Host "  Dislanacak yeni klasor yolu (bos=Iptal)"
        if (-not [string]::IsNullOrWhiteSpace($newPath) -and (Test-Path $newPath.Trim())) {
            Add-MpPreference -ExclusionPath $newPath.Trim() -ErrorAction Stop
            Write-Host "  [BASARILI] Klasor Defender dislama listesine eklendi." -ForegroundColor Green
        }
    } catch { Write-Host "  [HATA] $($_.Exception.Message)" -ForegroundColor Red }
}

function Invoke-PostFormatWizard {
    if (Get-Command "Show-ScreenTransition" -ErrorAction SilentlyContinue) { Show-ScreenTransition -Scrollable }
    if (Get-Command "Show-AppHeader" -ErrorAction SilentlyContinue) { Show-AppHeader -Scrollable }
    Write-Host ""
    Write-Host "  [21] | FORMAT SONRASI OTOMATIK KURULUM SIHIRBAZI" -ForegroundColor Green
    if (Get-Command "Draw-HorizontalLine" -ErrorAction SilentlyContinue) { Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-" }
    Write-Host ""
    Write-Host "  Bu sihirbaz format sonrasi temel adimlari sirayla uygular:" -ForegroundColor White
    Write-Host "    1. Sistem Geri Yukleme Noktasi olusturma (istege bagli)" -ForegroundColor Cyan
    Write-Host "    2. Gizlilik & Debloat ayarlari (Telemetri, Reklam, Copilot, Update Reboot)" -ForegroundColor Cyan
    Write-Host "    3. Konfor ayarlari (Dosya uzantilari, Bu Bilgisayar acilisi, Masaustu ikonlari)" -ForegroundColor Cyan
    Write-Host "    4. Nihai Performans guc plani aktivasyonu" -ForegroundColor Cyan
    Write-Host "    5. Kurulum Merkezi / Profil secimi & Lisanslama ekrani" -ForegroundColor Cyan
    Write-Host ""

    $start = Read-Host "  Sihirbazi baslatmak istiyor musunuz? (E/H)"
    if (-not $start -or $start.Trim().ToUpper() -ne "E") { return }

    if (Test-PostFormatAdmin) {
        $rp = Read-Host "  [Adim 1/5] Sistem Geri Yukleme Noktasi olusturulsun mu? (E/H)"
        if ($rp -and $rp.Trim().ToUpper() -eq "E") {
            try { Checkpoint-Computer -Description "AAU_Format_Sonrasi" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; Write-Host "  [BASARILI] Geri yukleme noktasi olusturuldu." -ForegroundColor Green }
            catch { Write-Host "  [BILGI] Geri yukleme noktasi olusturulamadi (sistem korumasi kapali olabilir)." -ForegroundColor Yellow }
        }
    }

    $deb = Read-Host "  [Adim 2/5] Gizlilik, Telemetri, Copilot ve Update Reboot korumalari uygulansin mi? (E/H)"
    if ($deb -and $deb.Trim().ToUpper() -eq "E") {
        Invoke-DebloatTelemetryAndAds
        Invoke-DisableCopilotWidgetsEdgeBg
        Invoke-DisableForcedUpdateReboot
    }

    $ui = Read-Host "  [Adim 3/5] Dosya uzantilari, Bu Bilgisayar acilisi ve masaustu ikonlari acilsin mi? (E/H)"
    if ($ui -and $ui.Trim().ToUpper() -eq "E") {
        try {
            $expPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Set-ItemProperty -Path $expPath -Name "HideFileExt" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $expPath -Name "LaunchTo" -Value 1 -Type DWord -Force
            $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
            if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
            Set-ItemProperty -Path $regPath -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Value 0 -Type DWord -Force
            Write-Host "  [BASARILI] Gezgin ve masaustu ikon ayarlari uygulandi." -ForegroundColor Green
        } catch {}
    }

    $pwr = Read-Host "  [Adim 4/5] Nihai Performans guc plani aktiflestirilsin mi? (E/H)"
    if ($pwr -and $pwr.Trim().ToUpper() -eq "E") { Invoke-UltimatePerformancePlan }

    $appsAns = Read-Host "  [Adim 5/5] Simdi Uygulama Kurulum Merkezini acmak ister misiniz? (E/H)"
    if ($appsAns -and $appsAns.Trim().ToUpper() -eq "E" -and (Get-Command "Invoke-Category01" -ErrorAction SilentlyContinue)) {
        Invoke-Category01
    }

    Write-Host "`n  [TEBRIKLER] Format Sonrasi Sihirbazi tamamlandi!" -ForegroundColor Green
    if (Get-Command "Wait-UserKeyPress" -ErrorAction SilentlyContinue) { Wait-UserKeyPress }
}

Export-ModuleMember -Function @(
    'Invoke-DebloatTelemetryAndAds',
    'Invoke-DisableCopilotWidgetsEdgeBg',
    'Invoke-DisableForcedUpdateReboot',
    'Invoke-RemoveBloatwareApps',
    'Show-DebloatPrivacyMenu',
    'Toggle-DesktopSystemIcons',
    'Toggle-ExplorerLaunchToThisPC',
    'Invoke-UltimatePerformancePlan',
    'Toggle-HibernationMode',
    'Invoke-GamingPerformanceTweaks',
    'Invoke-GpuAutoDetectDriver',
    'Invoke-WifiProfileBackupRestore',
    'Invoke-DefenderExclusionManager',
    'Invoke-PostFormatWizard'
)
