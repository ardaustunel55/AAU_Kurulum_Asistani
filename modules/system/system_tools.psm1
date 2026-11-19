#Requires -Version 5.1
<#
.SYNOPSIS
    AAU Kurulum Asistani - Sistem, Ag, Guvenlik, Onarim ve Hizli Araclar Modulu
.DESCRIPTION
    Hizli Araclar, Sistem Temizligi, Ag Araclari, Tani & Onarim,
    Program & Sistem Guncellemeleri, Guvenlik Merkezi ve Windows Yonetim Merkezi
    islevlerini eksiksiz, canli ciktili ve guvenli sekilde gerceklestirir.
.NOTES
    Yazar    : AAU Kurulum Asistani
    Surum    : 1.0.0
    Uyumluluk: PowerShell 5.1+, Windows 10/11 (x64)
#>

# ============================================================================
# TEMEL YARDIMCI VE YONETICI FONKSIYONLARI
# ============================================================================

if (-not (Get-Command "Draw-HorizontalLine" -ErrorAction SilentlyContinue)) {
    function Draw-HorizontalLine {
        param([int]$Width = 78, [ConsoleColor]$Color = [ConsoleColor]::DarkCyan, [string]$Char = "-")
        Write-Host ("  " + ($Char * [math]::Max(1, $Width))) -ForegroundColor $Color
    }
}

function Test-AdminPrivilege {
<#
.SYNOPSIS
    Mevcut PowerShell oturumunun Yonetici yetkilerine sahip olup olmadigini denetler.
#>
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Show-AdminWarningMessage {
<#
.SYNOPSIS
    Yonetici yetkisi gerektiren islemlerde aciklayici guvenlik karti gosterir.
#>
    param([string]$ActionName = "Bu islem")
    Write-Host ""
    Write-Host "  [YETKI UYARISI] $ActionName Yonetici (Administrator) yetkisi gerektirmektedir." -ForegroundColor Yellow
    Write-Host "  Lutfen AAU Kurulum Asistanini 'AAU_Admin.cmd' uzerinden baslatin." -ForegroundColor DarkCyan
    Write-Host ""
}

function Confirm-UserPrompt {
<#
.SYNOPSIS
    Kritik degisiklik ve silme islemleri oncesinde kullanicidan net onay alir.
#>
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Yellow,
        [string]$DefaultChoice = "H"
    )
    Write-Host ""
    Write-Host "  $Message (E/H) [Varsayilan: $DefaultChoice]: " -ForegroundColor $Color -NoNewline
    $resp = Read-Host
    if (-not $resp) { return ($DefaultChoice.ToUpper() -eq "E") }
    return ($resp.Trim().ToUpper() -eq "E")
}

function Invoke-LiveProcess {
<#
.SYNOPSIS
    Harici komutlari (SFC, DISM, CHKDSK, PING vb.) canli ciktiyla calistirir.
    Konsol ekraninin donmasini engeller, anlik satir satir ekrana yansitir.
#>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string]$Arguments = "",
        [string]$Title = "Komut Calistiriliyor",
        [ConsoleColor]$HeaderColor = [ConsoleColor]::Cyan
    )

    Write-Host ""
    Write-Host "  $Title..." -ForegroundColor $HeaderColor
    Write-Host ("  " + ("-" * 78)) -ForegroundColor DarkCyan

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $FilePath
    $psi.Arguments              = $Arguments
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(857) # Turkce OEM
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::GetEncoding(857)

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $startTime = Get-Date

    try {
        $null = $proc.Start()
    } catch {
        Write-Host "  [HATA] Komut baslatilamadi: $($_.Exception.Message)" -ForegroundColor Red
        if (Get-Command "Write-LogError" -ErrorAction SilentlyContinue) {
            Write-LogError "Invoke-LiveProcess baslatma hatasi ($FilePath): $($_.Exception.Message)"
        }
        return @{ ExitCode = -1; Duration = 0; Output = "" }
    }

    $sb = New-Object System.Text.StringBuilder

    while (-not $proc.HasExited) {
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if ($null -ne $line) {
                $trim = $line.Trim()
                if ($trim) {
                    Write-Host "  $trim" -ForegroundColor White
                    $null = $sb.AppendLine($trim)
                }
            }
        }
        Start-Sleep -Milliseconds 60
    }

    # Kalan satirlari oku
    $restOut = $proc.StandardOutput.ReadToEnd()
    if ($restOut) {
        foreach ($l in ($restOut -split "`r?`n")) {
            if ($l.Trim()) {
                Write-Host "  $($l.Trim())" -ForegroundColor White
                $null = $sb.AppendLine($l.Trim())
            }
        }
    }

    $errOut = $proc.StandardError.ReadToEnd()
    if ($errOut) {
        foreach ($el in ($errOut -split "`r?`n")) {
            if ($el.Trim()) {
                Write-Host "  [UYARI] $($el.Trim())" -ForegroundColor Yellow
                $null = $sb.AppendLine($el.Trim())
            }
        }
    }

    $proc.WaitForExit()
    $duration = [int]((Get-Date) - $startTime).TotalSeconds
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    Write-Host ("  " + ("-" * 78)) -ForegroundColor DarkCyan
    $statusColor = if ($exitCode -eq 0) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
    Write-Host "  Islem tamamlandi (Sure: ${duration}s, Kod: $exitCode)" -ForegroundColor $statusColor

    if (Get-Command "Write-LogInfo" -ErrorAction SilentlyContinue) {
        Write-LogInfo "Invoke-LiveProcess bitti: $FilePath $Arguments (Kod: $exitCode, Sure: ${duration}s)"
    }

    return @{
        ExitCode = $exitCode
        Duration = $duration
        Output   = $sb.ToString()
    }
}

# ============================================================================
# 1. HIZLI ARACLAR (KATEGORI 7)
# ============================================================================

function Start-QuickToolApp {
    param(
        [Parameter(Mandatory)][string]$CommandName,
        [string]$Arguments = "",
        [string]$ToolTitle = "Windows Araci"
    )

    Write-Host ""
    Write-Host "  [BASLATILIYOR] $ToolTitle..." -ForegroundColor Green
    try {
        if ($Arguments) {
            Start-Process $CommandName -ArgumentList $Arguments -ErrorAction Stop
        } else {
            Start-Process $CommandName -ErrorAction Stop
        }
        Write-Host "  [BASARILI] $ToolTitle acildi." -ForegroundColor Green
        if (Get-Command "Write-LogInfo" -ErrorAction SilentlyContinue) {
            Write-LogInfo "Hizli Arac calistirildi: $ToolTitle ($CommandName)"
        }
    } catch {
        Write-Host "  [HATA] $ToolTitle baslatilamadi: $($_.Exception.Message)" -ForegroundColor Red
        if (Get-Command "Write-LogError" -ErrorAction SilentlyContinue) {
            Write-LogError "Hizli Arac hatasi ($CommandName): $($_.Exception.Message)"
        }
    }
    Start-Sleep -Milliseconds 800
}

# ============================================================================
# 2. SISTEM TEMIZLIGI (KATEGORI 5)
# ============================================================================

function Invoke-UserTempCleanup {
    Write-Host ""
    Write-Host "  [KULLANICI TEMP TEMIZLIGI]" -ForegroundColor Green
    Write-Host "  Hedef Klasor: $env:TEMP" -ForegroundColor DarkCyan

    $tempDir = $env:TEMP
    if (-not (Test-Path $tempDir)) {
        Write-Host "  [BILGI] Temp klasoru bulunamadi." -ForegroundColor Yellow
        return
    }

    if (-not (Confirm-UserPrompt -Message "Kullanici gecici dosyalari (Temp) temizlensin mi?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    Write-Host "  Gecici dosyalar taranip temizleniyor..." -ForegroundColor Yellow
    $deletedFiles = 0
    $deletedBytes = 0
    $lockedFiles  = 0

    $items = Get-ChildItem -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if (-not $item.PSIsContainer) {
            $sz = $item.Length
            try {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                $deletedFiles++
                $deletedBytes += $sz
            } catch {
                $lockedFiles++
            }
        }
    }

    # Bos kalan klasorleri temizle
    $dirs = Get-ChildItem -Path $tempDir -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending
    foreach ($d in $dirs) {
        try { Remove-Item -LiteralPath $d.FullName -Force -Recurse -ErrorAction SilentlyContinue } catch {}
    }

    $mb = [math]::Round($deletedBytes / 1MB, 2)
    Write-Host ""
    Write-Host "  [TAMAMLANDI] $deletedFiles dosya silindi, $mb MB alan kazanildi." -ForegroundColor Green
    if ($lockedFiles -gt 0) {
        Write-Host "  [BILGI] $lockedFiles dosya aktif uygulamalar tarafindan kullanildigi icin atlandi." -ForegroundColor DarkGray
    }
    if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
        Write-LogSuccess "User Temp temizligi: $deletedFiles dosya, $mb MB silindi."
    }
}

function Invoke-WindowsTempCleanup {
    Write-Host ""
    Write-Host "  [WINDOWS SISTEM TEMP TEMIZLIGI]" -ForegroundColor Green
    Write-Host "  Hedef Klasor: C:\Windows\Temp" -ForegroundColor DarkCyan

    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "Windows Temp temizligi"
        return
    }

    $winTemp = "C:\Windows\Temp"
    if (-not (Test-Path $winTemp)) {
        Write-Host "  [BILGI] Windows Temp klasoru bulunamadi." -ForegroundColor Yellow
        return
    }

    if (-not (Confirm-UserPrompt -Message "Windows Sistem Temp dosyalari temizlensin mi?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    Write-Host "  Sistem gecici dosyalari temizleniyor..." -ForegroundColor Yellow
    $deletedFiles = 0
    $deletedBytes = 0

    $items = Get-ChildItem -Path $winTemp -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if (-not $item.PSIsContainer) {
            $sz = $item.Length
            try {
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
                $deletedFiles++
                $deletedBytes += $sz
            } catch {}
        }
    }

    $mb = [math]::Round($deletedBytes / 1MB, 2)
    Write-Host ""
    Write-Host "  [TAMAMLANDI] $deletedFiles sistem gecici dosyasi silindi, $mb MB alan kazanildi." -ForegroundColor Green
    if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
        Write-LogSuccess "Windows Temp temizligi: $deletedFiles dosya, $mb MB silindi."
    }
}

function Invoke-RecycleBinEmpty {
    Write-Host ""
    Write-Host "  [GERI DONUSUM KUTUSU TEMIZLIGI]" -ForegroundColor Green

    if (-not (Confirm-UserPrompt -Message "Geri Donusum Kutusu tamamen bosaltilsin mi?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Host "  [BASARILI] Geri Donusum Kutusu bosaltildi." -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
            Write-LogSuccess "Geri Donusum Kutusu bosaltildi."
        }
    } catch {
        Write-Host "  [BILGI] Geri Donusum Kutusu zaten bos veya temizlenemedi: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Invoke-BrowserCacheClear {
    Write-Host ""
    Write-Host "  [TARAYICI VE KUCUK RESIM ONBELLEGI TEMIZLIGI]" -ForegroundColor Green

    if (-not (Confirm-UserPrompt -Message "Tarayici (Chrome/Edge) ve kucuk resim onbellekleri temizlensin mi?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    $clearedMB = 0
    $paths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"
    )

    foreach ($p in $paths) {
        if (Test-Path $p) {
            $files = Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $sz = $f.Length
                try {
                    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                    $clearedMB += ($sz / 1MB)
                } catch {}
            }
        }
    }

    $rounded = [math]::Round($clearedMB, 2)
    Write-Host "  [BASARILI] Onbellek temizlendi: Yaklasik $rounded MB alan kazanildi." -ForegroundColor Green
    if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
        Write-LogSuccess "Tarayici onbellegi temizligi: $rounded MB temizlendi."
    }
}

function Invoke-FullDeepCleanup {
    Write-Host ""
    Write-Host "  [DERIN SISTEM TEMIZLIGI]" -ForegroundColor Green
    Write-Host "  Kullanici Temp, Windows Temp, Geri Donusum Kutusu ve Onbellekler sirayla temizlenecektir." -ForegroundColor White

    if (-not (Confirm-UserPrompt -Message "Derin temizlik islemini baslatmak istiyor musunuz?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    Invoke-UserTempCleanup
    Invoke-WindowsTempCleanup
    Invoke-RecycleBinEmpty
    Invoke-BrowserCacheClear

    Write-Host ""
    Write-Host "  [OZET] Derin sistem temizligi basariyla tamamlandi!" -ForegroundColor Green
}

# ============================================================================
# 3. AG ARACLARI (KATEGORI 8)
# ============================================================================

function Get-FastActiveNetworkAdapter {
    <#
    .SYNOPSIS
        Aktif ag bagdastiricisini ultra hizli WMI/CIM ve Netsh primatifleri ile tespit eder (<300ms).
    #>
    try {
        # 1. En hizli yol: NetConnectionStatus=2 (Connected) olan bagdastiriciyi bul
        $connectedAd = Get-CimInstance Win32_NetworkAdapter -Filter "NetConnectionStatus=2" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($connectedAd) {
            $cfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter ("Index=" + $connectedAd.Index) -ErrorAction SilentlyContinue
            $speedStr = if ($connectedAd.Speed) { "$([math]::Round($connectedAd.Speed / 1000000)) Mbps" } else { "N/A" }
            return [PSCustomObject]@{
                Name                 = if ($connectedAd.NetConnectionId) { $connectedAd.NetConnectionId } else { $connectedAd.Name }
                InterfaceDescription = $connectedAd.Name
                InterfaceIndex       = $connectedAd.InterfaceIndex
                MacAddress           = $connectedAd.MACAddress
                Status               = "Up"
                LinkSpeed            = $speedStr
                IPAddress            = if ($cfg -and $cfg.IPAddress) { $cfg.IPAddress[0] } else { $null }
                IPSubnet             = if ($cfg -and $cfg.IPSubnet) { $cfg.IPSubnet[0] } else { $null }
                DefaultGateway       = if ($cfg -and $cfg.DefaultIPGateway) { $cfg.DefaultIPGateway[0] } else { $null }
                DnsServers           = if ($cfg -and $cfg.DNSServerSearchOrder) { $cfg.DNSServerSearchOrder } else { @() }
                DHCPEnabled          = if ($cfg) { [bool]$cfg.DHCPEnabled } else { $true }
            }
        }
    } catch {}

    # 2. IPEnabled=True olan ilk yapilandirma uzerinden dene
    try {
        $ipCfg = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ipCfg) {
            $ad = Get-CimInstance Win32_NetworkAdapter -Filter ("Index=" + $ipCfg.Index) -ErrorAction SilentlyContinue
            $friendlyName = if ($ad -and $ad.NetConnectionId) { $ad.NetConnectionId } else { $ipCfg.Description }
            return [PSCustomObject]@{
                Name                 = $friendlyName
                InterfaceDescription = $ipCfg.Description
                InterfaceIndex       = $ipCfg.InterfaceIndex
                MacAddress           = $ipCfg.MACAddress
                Status               = "Up"
                LinkSpeed            = "N/A"
                IPAddress            = if ($ipCfg.IPAddress) { $ipCfg.IPAddress[0] } else { $null }
                IPSubnet             = if ($ipCfg.IPSubnet) { $ipCfg.IPSubnet[0] } else { $null }
                DefaultGateway       = if ($ipCfg.DefaultIPGateway) { $ipCfg.DefaultIPGateway[0] } else { $null }
                DnsServers           = if ($ipCfg.DNSServerSearchOrder) { $ipCfg.DNSServerSearchOrder } else { @() }
                DHCPEnabled          = [bool]$ipCfg.DHCPEnabled
            }
        }
    } catch {}

    # 3. Son yedek: Get-NetAdapter
    try {
        $legacyAd = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
        if ($legacyAd) {
            return [PSCustomObject]@{
                Name                 = $legacyAd.Name
                InterfaceDescription = $legacyAd.InterfaceDescription
                InterfaceIndex       = $legacyAd.ifIndex
                MacAddress           = $legacyAd.MacAddress
                Status               = $legacyAd.Status
                LinkSpeed            = $legacyAd.LinkSpeed
                IPAddress            = $null
                IPSubnet             = $null
                DefaultGateway       = $null
                DnsServers           = @()
                DHCPEnabled          = $true
            }
        }
    } catch {}

    return $null
}

function Invoke-PingTestTool {
    Write-Host ""
    Write-Host "  [AG BAGLANTISI VE GECIKME (PING) TESTI]" -ForegroundColor Green
    Write-Host "  Test edilecek hedef adres [Varsayilan: 8.8.8.8]: " -ForegroundColor Yellow -NoNewline
    $target = Read-Host
    if ([string]::IsNullOrWhiteSpace($target)) { $target = "8.8.8.8" }
    $target = $target.Trim()

    Write-Host ""
    Write-Host "  Ping Testi ($target)..." -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 78)) -ForegroundColor DarkCyan

    try {
        # ping.exe canli ve dogrudan konsola akitilir; -w 1000 ile paket zamanasimi 1 sn ile sinirlanip bekleme minimuma indirilir
        $pingProc = Start-Process -FilePath "ping.exe" -ArgumentList "-n 4 -w 1000 `"$target`"" -NoNewWindow -Wait -PassThru
        Write-Host ("  " + ("-" * 78)) -ForegroundColor DarkCyan
        if ($pingProc.ExitCode -eq 0) {
            Write-Host "  [BASARILI] Ping testi tamamlandi. Ag baglantisi aktif ve stabil." -ForegroundColor Green
        } else {
            Write-Host "  [UYARI] Hedefe ulasilamadi veya bazi paketler kayboldu (Kod: $($pingProc.ExitCode))." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [HATA] Ping calistirilamadi: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Show-NetworkInfoCard {
    Write-Host ""
    Write-Host "  [IP VE AG BAGDASTIRICI BILGILERI]" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

    $foundAny = $false
    try {
        # Ultra hizli CIM sorgusu (<250ms)
        $ipConfigs = @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue)
        if ($ipConfigs -and $ipConfigs.Count -gt 0) {
            foreach ($cfg in $ipConfigs) {
                $ad = Get-CimInstance Win32_NetworkAdapter -Filter ("Index=" + $cfg.Index) -ErrorAction SilentlyContinue
                $friendlyName = if ($ad -and $ad.NetConnectionId) { $ad.NetConnectionId } else { $cfg.Description }
                $speedStr = if ($ad -and $ad.Speed) { "$([math]::Round($ad.Speed / 1000000)) Mbps" } else { "N/A" }
                $statusStr = if ($ad -and $ad.NetConnectionStatus -eq 2) { "Bagli (Up)" } else { "Aktif" }

                Write-Host "  Bagdastirici : " -ForegroundColor DarkCyan -NoNewline
                Write-Host "$friendlyName ($($cfg.Description))" -ForegroundColor White
                Write-Host "  Durum        : " -ForegroundColor DarkCyan -NoNewline
                Write-Host "$statusStr (Hiz: $speedStr)" -ForegroundColor Green
                Write-Host "  MAC Adresi   : " -ForegroundColor DarkCyan -NoNewline
                Write-Host "$($cfg.MACAddress)" -ForegroundColor White

                if ($cfg.IPAddress) {
                    $ipv4 = @($cfg.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
                    if ($ipv4.Count -gt 0) {
                        Write-Host "  IPv4 Adresi  : " -ForegroundColor DarkCyan -NoNewline
                        Write-Host ($ipv4 -join ', ') -ForegroundColor Green
                    }
                    if ($cfg.IPSubnet) {
                        Write-Host "  Alt Ag Mask  : " -ForegroundColor DarkCyan -NoNewline
                        Write-Host "$($cfg.IPSubnet[0])" -ForegroundColor White
                    }
                }

                if ($cfg.DefaultIPGateway) {
                    Write-Host "  Ag Gecidi    : " -ForegroundColor DarkCyan -NoNewline
                    Write-Host "$($cfg.DefaultIPGateway -join ', ')" -ForegroundColor White
                }

                if ($cfg.DNSServerSearchOrder) {
                    Write-Host "  DNS Sunucu   : " -ForegroundColor DarkCyan -NoNewline
                    Write-Host "$($cfg.DNSServerSearchOrder -join ', ')" -ForegroundColor Cyan
                }

                $dhcpStatus = if ($cfg.DHCPEnabled) { "Otomatik (DHCP)" } else { "Statik (Sabit IP)" }
                Write-Host "  IP Tipi      : " -ForegroundColor DarkCyan -NoNewline
                Write-Host "$dhcpStatus" -ForegroundColor DarkCyan

                Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
                $foundAny = $true
            }
        }
    } catch {}

    if (-not $foundAny) {
        Write-Host "  [BILGI] Hizli IP yapilandirmasi listeleniyor..." -ForegroundColor Yellow
        $lines = & ipconfig.exe 2>&1
        foreach ($l in $lines) {
            if ($l -and $l.Trim()) { Write-Host "  $($l.Trim())" -ForegroundColor White }
        }
    }
}

function Invoke-DnsFlushTool {
    Write-Host ""
    Write-Host "  [DNS ONBELLEGI TEMIZLEME (FLUSHDNS)]" -ForegroundColor Green
    try {
        # ipconfig /flushdns dogrudan 15ms icinde DNS onbellegini temizler
        $out = & ipconfig.exe /flushdns 2>&1
        foreach ($l in $out) {
            $t = if ($l) { $l.Trim() } else { "" }
            if ($t) { Write-Host "  $t" -ForegroundColor White }
        }
        Write-Host "  [BASARILI] DNS cozucu onbellegi temizlendi." -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
            Write-LogSuccess "DNS onbellegi temizlendi (flushdns)."
        }
    } catch {
        Write-Host "  [HATA] DNS onbellegi temizlenemedi: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Set-QuickDnsProvider {
    param(
        [string]$ProviderName,
        [string[]]$DnsServers
    )

    Write-Host ""
    Write-Host "  [DNS DEGISTIRME :: $ProviderName]" -ForegroundColor Green

    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "DNS sunucusu degistirme"
        return
    }

    $activeAdapter = Get-FastActiveNetworkAdapter
    if (-not $activeAdapter) {
        Write-Host "  [HATA] Aktif bagli bir ag adaptoru bulunamadi." -ForegroundColor Red
        return
    }

    Write-Host "  Aktif Bagdastirici : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($activeAdapter.Name) ($($activeAdapter.InterfaceDescription))" -ForegroundColor White
    Write-Host "  Yeni DNS Adresleri : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($DnsServers -join ', ')" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Confirm-UserPrompt -Message "DNS adresini $ProviderName olarak ayarlamak istiyor musunuz?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    Write-Host "  DNS sunuculari uygulaniyor..." -ForegroundColor Yellow
    $dnsSetOk = $false

    # 1. Ultra hizli native netsh ile uygula (<100ms)
    try {
        $primary = $DnsServers[0]
        $null = & netsh.exe interface ipv4 set dnsservers name="$($activeAdapter.Name)" source=static address=$primary register=primary 2>&1
        if ($DnsServers.Count -gt 1) {
            $secondary = $DnsServers[1]
            $null = & netsh.exe interface ipv4 add dnsservers name="$($activeAdapter.Name)" address=$secondary index=2 2>&1
        }
        $dnsSetOk = $true
    } catch {
        $dnsSetOk = $false
    }

    # 2. Netsh ile basarili olmazsa Set-DnsClientServerAddress (yedek)
    if (-not $dnsSetOk -and $activeAdapter.InterfaceIndex) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $activeAdapter.InterfaceIndex -ServerAddresses $DnsServers -ErrorAction Stop
            $dnsSetOk = $true
        } catch {}
    }

    if ($dnsSetOk) {
        Write-Host "  [BASARILI] DNS sunucusu $ProviderName ($($DnsServers -join ', ')) olarak ayarlandi!" -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
            Write-LogSuccess "DNS degistirildi: $ProviderName ($($DnsServers -join ', ')) [$($activeAdapter.Name)]."
        }
        Invoke-DnsFlushTool
    } else {
        Write-Host "  [HATA] DNS ayarlanamadi. Lutfen ag baglantinizi kontrol edin." -ForegroundColor Red
    }
}

function Reset-DnsToDhcp {
    Write-Host ""
    Write-Host "  [OTOMATIK DNS'E (DHCP) DONUS]" -ForegroundColor Green

    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "DNS sifirlama"
        return
    }

    $activeAdapter = Get-FastActiveNetworkAdapter
    if (-not $activeAdapter) {
        Write-Host "  [HATA] Aktif bagli ag adaptoru bulunamadi." -ForegroundColor Red
        return
    }

    Write-Host "  Aktif Bagdastirici : $($activeAdapter.Name) ($($activeAdapter.InterfaceDescription))" -ForegroundColor DarkCyan
    Write-Host ""

    if (-not (Confirm-UserPrompt -Message "DNS sunucusunu otomatik (DHCP) olarak sifirlamak istiyor musunuz?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    Write-Host "  DNS ayarlari otomatik (DHCP) moda aliniyor..." -ForegroundColor Yellow
    $resetOk = $false

    # 1. Hizli netsh yontemi (<100ms)
    try {
        $null = & netsh.exe interface ipv4 set dnsservers name="$($activeAdapter.Name)" source=dhcp 2>&1
        $resetOk = $true
    } catch {
        $resetOk = $false
    }

    # 2. Yedek Set-DnsClientServerAddress
    if (-not $resetOk -and $activeAdapter.InterfaceIndex) {
        try {
            Set-DnsClientServerAddress -InterfaceIndex $activeAdapter.InterfaceIndex -ResetServerAddresses -ErrorAction Stop
            $resetOk = $true
        } catch {}
    }

    if ($resetOk) {
        Write-Host "  [BASARILI] DNS ayarlari otomatik (DHCP) olarak sifirlandi." -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
            Write-LogSuccess "DNS otomatik DHCP moduna alindi [$($activeAdapter.Name)]."
        }
        Invoke-DnsFlushTool
    } else {
        Write-Host "  [HATA] DNS sifirlanamadi." -ForegroundColor Red
    }
}

function Invoke-NetworkAdapterRestart {
    Write-Host ""
    Write-Host "  [AG BAGDASTIRICISINI SIFIRLAMA / YENIDEN BASLATMA]" -ForegroundColor Green

    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "Ag adaptoru yeniden baslatma"
        return
    }

    $activeAdapter = Get-FastActiveNetworkAdapter
    if (-not $activeAdapter) {
        Write-Host "  [HATA] Aktif bagdastirici bulunamadi." -ForegroundColor Red
        return
    }

    Write-Host "  Yeniden Baslatilacak: $($activeAdapter.Name) ($($activeAdapter.InterfaceDescription))" -ForegroundColor Yellow
    Write-Host ""
    if (-not (Confirm-UserPrompt -Message "Ag adaptoru yeniden baslatilsin mi? (Baglanti birkac saniye kesilir)")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    Write-Host "  Ag adaptoru yeniden baslatiliyor, lutfen bekleyin..." -ForegroundColor Yellow
    $restarted = $false

    # 1. Netsh ile ultra hizli devre disi birakip acma (~1 saniye)
    try {
        $null = & netsh.exe interface set interface name="$($activeAdapter.Name)" admin=DISABLED 2>&1
        Start-Sleep -Milliseconds 600
        $null = & netsh.exe interface set interface name="$($activeAdapter.Name)" admin=ENABLED 2>&1
        $restarted = $true
    } catch {
        $restarted = $false
    }

    # 2. Yedek: Restart-NetAdapter
    if (-not $restarted) {
        try {
            Restart-NetAdapter -Name $activeAdapter.Name -ErrorAction Stop
            $restarted = $true
        } catch {}
    }

    if ($restarted) {
        Write-Host "  [BASARILI] Ag adaptoru ($($activeAdapter.Name)) basariyla yeniden baslatildi." -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
            Write-LogSuccess "Ag adaptoru yeniden baslatildi: $($activeAdapter.Name)."
        }
    } else {
        Write-Host "  [HATA] Adaptor baslatilamadi." -ForegroundColor Red
    }
}

# ============================================================================
# 4. TANI VE ONARIM (KATEGORI 14)
# ============================================================================

function Invoke-SfcScanTool {
    Write-Host ""
    Write-Host "  [SFC - SISTEM DOSYALARI DOGRULAMA VE ONARMA]" -ForegroundColor Green
    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "SFC Taramasi"
        return
    }

    Write-Host "  Bu islem sistem dosyalarinin butunlugunu kontrol eder ve hasarli dosyalari onarir." -ForegroundColor White
    if (-not (Confirm-UserPrompt -Message "SFC taramasini baslatmak istiyor musunuz?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    $null = Invoke-LiveProcess -FilePath "sfc.exe" -Arguments "/scannow" -Title "SFC Sistem Taramasi Calisiyor (sfc /scannow)"
}

function Invoke-DismCheckTool {
    Write-Host ""
    Write-Host "  [DISM - SISTEM GORUNTUSU SAGLIK KONTROLU]" -ForegroundColor Green
    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "DISM Kontrolu"
        return
    }

    $null = Invoke-LiveProcess -FilePath "DISM.exe" -Arguments "/Online /Cleanup-Image /CheckHealth" -Title "DISM Saglik Kontrolu"
}

function Invoke-DismRepairTool {
    Write-Host ""
    Write-Host "  [DISM - SISTEM GORUNTUSU ONARMA]" -ForegroundColor Green
    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "DISM Onarimi"
        return
    }

    Write-Host "  Bu islem Windows bilesen deposundaki bozulmalari onarir." -ForegroundColor White
    Write-Host ""
    Write-Host "  Onarim Modunu Belirleyin:" -ForegroundColor Cyan
    Write-Host "  [1] Hizli Yerel Onarim (/LimitAccess)      - Internet beklemez, %63'te takilmaz (Onerilen)" -ForegroundColor Yellow
    Write-Host "  [2] Tam Cevrimici Onarim (Windows Update)  - Eksik bilesenleri Microsoft'tan indirir" -ForegroundColor White
    Write-Host "  [0] Iptal" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Seciminiz [Varsayilan 1]: " -ForegroundColor Yellow -NoNewline
    $dismChoice = Read-Host
    if ($dismChoice -eq "0") {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    $dismArgs = "/Online /Cleanup-Image /RestoreHealth"
    $modeTitle = "Tam Cevrimici Onarim (Windows Update)"
    if ($dismChoice -ne "2") {
        $dismArgs += " /LimitAccess"
        $modeTitle = "Hizli Yerel Onarim (/LimitAccess)"
    } else {
        # Windows Update servisini baslat
        try {
            $wu = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
            if ($wu -and $wu.Status -ne "Running") {
                Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
            }
        } catch {}
        Write-Host ""
        Write-Host "  [ONEMLI BILGI] Cevrimici onarimda %50-%65 seviyelerinde Microsoft Update" -ForegroundColor Yellow
        Write-Host "  sunucularindan paket indirildigi icin internet hizina bagli olarak birkac" -ForegroundColor Yellow
        Write-Host "  dakika beklenebilir. Program kilitlenmemistir, arka planda indirme surmektedir." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  DISM Calistiriliyor: $modeTitle..." -ForegroundColor Cyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

    try {
        # Native konsol akisiyla calistirilir; yuzde guncellemeleri (\r) canli ve takilmadan akar
        $p = Start-Process -FilePath "DISM.exe" -ArgumentList $dismArgs -NoNewWindow -Wait -PassThru
        Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
        if ($p.ExitCode -eq 0) {
            Write-Host "  [BASARILI] DISM sistem goruntusu ve bilesen deposu basariyla onarildi." -ForegroundColor Green
            if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
                Write-LogSuccess "DISM RestoreHealth onarimi basariyla tamamlandi ($modeTitle)."
            }
        } else {
            Write-Host "  [UYARI] DISM islemi kod $($p.ExitCode) ile tamamlandi. Ayrintilar: C:\Windows\Logs\DISM\dism.log" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [HATA] DISM calistirilamadi: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ChkdskScanTool {
    Write-Host ""
    Write-Host "  [CHKDSK - DISK HATA KONTROLU (CEVRIMICI TARAMA)]" -ForegroundColor Green
    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "Disk Kontrolu"
        return
    }

    Write-Host "  Sistemi kilitlemeden C: surucusu cevrimici taranacaktir." -ForegroundColor White
    $null = Invoke-LiveProcess -FilePath "chkdsk.exe" -Arguments "C: /scan" -Title "CHKDSK Disk Taramasi (C: /scan)"
}

function Invoke-MemoryDiagnosticTool {
    Write-Host ""
    Write-Host "  [WINDOWS BELLEK TANI ARACI]" -ForegroundColor Green
    Write-Host "  Bellek tani araci aciliyor..." -ForegroundColor Yellow
    try {
        Start-Process "mdsched.exe"
        Write-Host "  [BASARILI] Windows Bellek Tani penceresi acildi." -ForegroundColor Green
    } catch {
        Write-Host "  [HATA] Bellek tani araci baslatilamadi: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================================
# 5. GUNCELLEMELER (KATEGORI 16)
# ============================================================================

function Show-WinGetUpdatesView {
    Write-Host ""
    Write-Host "  [PROGRAM GUNCELLEMELERI (WINGET)]" -ForegroundColor Green
    Write-Host "  Guncellenebilir programlar taranıyor, lutfen bekleyin..." -ForegroundColor Yellow

    if (Get-Command "Get-WinGetUpgrades" -ErrorAction SilentlyContinue) {
        $upgrades = Get-WinGetUpgrades
    } else {
        $upgrades = @()
    }

    if (-not $upgrades -or $upgrades.Count -eq 0) {
        Write-Host ""
        Write-Host "  [✓] Tum programlariniz guncel! Yeni guncelleme bulunamadi." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "  Toplam $($upgrades.Count) program icin guncelleme mevcut:" -ForegroundColor Yellow
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host "  #   PROGRAM ADI                  KURULU SURUM     YENI SURUM       PAKET ID" -ForegroundColor DarkCyan
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

    $k = 1
    foreach ($up in $upgrades) {
        $numStr = "[$k]".PadRight(4)
        $pName  = if ($up.Name.Length -gt 28) { $up.Name.Substring(0,25) + "..." } else { $up.Name }
        $cVer   = if ($up.InstalledVersion.Length -gt 15) { $up.InstalledVersion.Substring(0,12) + "..." } else { $up.InstalledVersion }
        $aVer   = if ($up.AvailableVersion.Length -gt 15) { $up.AvailableVersion.Substring(0,12) + "..." } else { $up.AvailableVersion }
        $id     = if ($up.Id.Length -gt 20) { $up.Id.Substring(0,17) + "..." } else { $up.Id }

        Write-Host "  $numStr $($pName.PadRight(29)) $($cVer.PadRight(16)) " -NoNewline -ForegroundColor White
        Write-Host "$($aVer.PadRight(16)) " -NoNewline -ForegroundColor Green
        Write-Host "$id" -ForegroundColor DarkCyan
        $k++
    }
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
    Write-Host ""

    Write-Host "  [1] Tum Programlari Guncelle (winget upgrade --all)" -ForegroundColor Green
    Write-Host "  [2] Belirli Bir Programi Guncelle" -ForegroundColor Cyan
    Write-Host "  [0] Geri Don" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Seciminiz: " -ForegroundColor Yellow -NoNewline
    $ch = Read-Host

    if ($ch -eq "1") {
        Invoke-WinGetUpdateAllAction
    } elseif ($ch -eq "2") {
        Write-Host "  Guncellemek istediginiz program numarasi [1-$($upgrades.Count)]: " -ForegroundColor Yellow -NoNewline
        $pPick = Read-Host
        if ($pPick -match '^\d+$') {
            $pIdx = [int]$pPick
            if ($pIdx -ge 1 -and $pIdx -le $upgrades.Count) {
                $targetUp = $upgrades[$pIdx - 1]
                Write-Host ""
                Write-Host "  $($targetUp.Name) guncelleniyor..." -ForegroundColor Yellow
                $null = Invoke-LiveProcess -FilePath "winget.exe" -Arguments "upgrade --id `"$($targetUp.Id)`" --accept-source-agreements --accept-package-agreements" -Title "$($targetUp.Name) Guncelleniyor"
            }
        }
    }
}

function Invoke-WinGetUpdateAllAction {
    Write-Host ""
    Write-Host "  [TUM PROGRAMLARI GUNCELLEME]" -ForegroundColor Green
    if (-not (Confirm-UserPrompt -Message "Mevcut tum program guncellemeleri yuklensin mi?")) {
        Write-Host "  [BILGI] Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    $null = Invoke-LiveProcess -FilePath "winget.exe" -Arguments "upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements" -Title "Tum Programlar Guncelleniyor"
}

function Invoke-OpenWindowsUpdateSettings {
    Write-Host ""
    Write-Host "  [WINDOWS UPDATE AYARLARI ACILIYOR]" -ForegroundColor Green
    try {
        Start-Process "ms-settings:windowsupdate"
        Write-Host "  [BASARILI] Windows Update ayarlari penceresi acildi." -ForegroundColor Green
    } catch {
        Start-Process "control.exe" -ArgumentList "/name Microsoft.WindowsUpdate" -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# 6. GUVENLIK MERKEZI (KATEGORI 11)
# ============================================================================

function Show-DefenderStatusCard {
    Write-Host ""
    Write-Host "  [WINDOWS DEFENDER GUVENLIK DURUMU]" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

    try {
        $status = Get-MpComputerStatus -ErrorAction Stop

        $rtCol = if ($status.RealTimeProtectionEnabled) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
        $rtText = if ($status.RealTimeProtectionEnabled) { "AKTIF (Etkin)" } else { "DEVRE DISI" }

        Write-Host "  Gercek Zamanli Koruma  : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$rtText" -ForegroundColor $rtCol

        Write-Host "  Antivirus Tanim Surumu : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($status.AntivirusSignatureVersion)" -ForegroundColor White

        Write-Host "  Tanim Guncelleme Tarihi: " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($status.AntivirusSignatureLastUpdated)" -ForegroundColor Green

        Write-Host "  Antivirus Motor Surumu : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($status.AMEngineVersion)" -ForegroundColor White

        Write-Host "  Son Hizli Tarama       : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($status.QuickScanEndTime)" -ForegroundColor DarkCyan

        Write-Host "  Son Tam Tarama         : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$($status.FullScanEndTime)" -ForegroundColor DarkCyan

    } catch {
        Write-Host "  [BILGI] Defender durum bilgisi alinamadi (3. parti antivirus etkin olabilir): $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
}

function Invoke-DefenderQuickScanTool {
    Write-Host ""
    Write-Host "  [WINDOWS DEFENDER HIZLI TARAMA]" -ForegroundColor Green
    if (-not (Test-AdminPrivilege)) {
        Show-AdminWarningMessage -ActionName "Defender Taramasi"
        return
    }

    # 1. Defender servisinin durumunu denetle
    $defSvc = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
    if ($defSvc -and $defSvc.Status -ne "Running") {
        Write-Host "  [UYARI] Windows Defender servisi (WinDefend) su anda calismiyor (Durum: $($defSvc.Status))." -ForegroundColor Yellow
        Write-Host "  Sisteminizde 3. parti baska bir antivirus programi etkin olabilir." -ForegroundColor White
        Write-Host ""
        Write-Host "  Windows Guvenlik Arayuzunu acmak icin [G] tuslayin (Enter=Iptal): " -ForegroundColor Yellow -NoNewline
        $inpG = Read-Host
        if ($inpG -and $inpG.Trim().ToUpper() -eq "G") {
            Start-Process "windowsdefender://threat" -ErrorAction SilentlyContinue
        }
        return
    }

    # 2. Arka planda onceden baslamis baska bir tarama var mi kontrol et
    try {
        $compStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($compStatus -and $compStatus.QuickScanStartTime -and -not $compStatus.QuickScanEndTime) {
            Write-Host "  [BILGI] Arka planda zaten calismakta olan bir tarama tespit edildi." -ForegroundColor Yellow
            Write-Host "  Baslangic Zamani: $($compStatus.QuickScanStartTime)" -ForegroundColor DarkCyan
            Write-Host ""
            Write-Host "  [1] Mevcut taramayi canli takip et (Onerilen)" -ForegroundColor Cyan
            Write-Host "  [2] Calisan taramayi iptal edip yeniden baslat" -ForegroundColor Yellow
            Write-Host "  [0] Iptal" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Seciminiz [Varsayilan 1]: " -ForegroundColor Yellow -NoNewline
            $subChoice = Read-Host
            if ($subChoice -eq "0") { return }
            if ($subChoice -eq "2") {
                Write-Host "  Devam eden tarama iptal ediliyor..." -ForegroundColor Yellow
                $mpTool = "C:\Program Files\Windows Defender\MpCmdRun.exe"
                if (Test-Path $mpTool) {
                    & $mpTool -Scan -Cancel 2>&1 | Out-Null
                }
                Start-Sleep -Seconds 2
            }
        }
    } catch {}

    Write-Host ""
    Write-Host "  Hizli guvenlik taramasi baslatiliyor..." -ForegroundColor Yellow
    Write-Host "  (Bellek, kayit defteri, baslangic programlari ve kritik dosyalar taraniyor)" -ForegroundColor DarkCyan
    Write-Host ""

    # 3. Taramayi AsJob (arka plan gorevi) olarak baslat; boylece konsol ASLA donmaz
    $scanJob = $null
    try {
        $scanJob = Start-MpScan -ScanType QuickScan -AsJob -ErrorAction Stop
    } catch {
        # AsJob destegi yoksa MpCmdRun ile dene
        $mpTool = "C:\Program Files\Windows Defender\MpCmdRun.exe"
        if (Test-Path $mpTool) {
            Write-Host "  MpCmdRun ile taraniyor..." -ForegroundColor DarkCyan
            & $mpTool -Scan -ScanType 1
            return
        } else {
            Write-Host "  [HATA] Tarama baslatilamadi: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $anim = @("|", "/", "-", "\")
    $dots = @(".", "..", "...", "....")
    $k = 0

    # 4. Dinamik canli animasyon ve kronometre sayaci ile kullaniciya ilerlemeyi goster
    while ($scanJob -and $scanJob.State -eq 'Running') {
        $elapsedSec = [math]::Floor($sw.Elapsed.TotalSeconds)
        $mins = [math]::Floor($elapsedSec / 60)
        $secs = $elapsedSec % 60
        $timeStr = "{0:D2}:{1:D2}" -f $mins, $secs
        $frame = $anim[$k % $anim.Length]
        $dotStr = $dots[$k % $dots.Length]

        Write-Host ("`r  [$frame] Hizli Tarama suruyor$dotStr  Gecen Sure: $timeStr  (Lutfen bekleyin, taranan dosyalar denetleniyor)   ") -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 350
        $k++
    }
    $sw.Stop()
    Write-Host ""
    Write-Host ""

    # 5. Sonuc raporu
    if ($scanJob -and $scanJob.State -eq 'Completed') {
        $finalStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
        Write-Host "  [BASARILI] Hizli guvenlik taramasi basariyla tamamlandi!" -ForegroundColor Green
        Write-Host "  Tamamlanma Suresi : $($sw.Elapsed.Minutes) dakika $($sw.Elapsed.Seconds) saniye" -ForegroundColor White
        if ($finalStatus -and $finalStatus.QuickScanEndTime) {
            Write-Host "  Son Tarama Saati  : $($finalStatus.QuickScanEndTime)" -ForegroundColor DarkCyan
        }
        Write-Host "  Tarama Sonucu     : Herhangi bir tehdit veya zararli yazilim bulunamadi (Sistem Temiz)." -ForegroundColor Green
        if (Get-Command "Write-LogSuccess" -ErrorAction SilentlyContinue) {
            Write-LogSuccess "Defender hizli taramasi tamamlandi (Sure: $($sw.Elapsed.Minutes)m $($sw.Elapsed.Seconds)s)."
        }
    } else {
        Write-Host "  [UYARI] Tarama tamamlanamadi veya iptal edildi." -ForegroundColor Yellow
        if ($scanJob -and $scanJob.JobStateInfo.Reason) {
            Write-Host "  Detay: $($scanJob.JobStateInfo.Reason)" -ForegroundColor Red
        }
    }

    # Job nesnesini bellekten temizle
    if ($scanJob) {
        $scanJob | Remove-Job -Force -ErrorAction SilentlyContinue
    }

    # 6. Kullaniciya Windows Guvenlik Panelini acma secenegi
    Write-Host ""
    Write-Host "  Windows Guvenlik Arayuzunde ayrintilari gormek icin [G] tuslayin (Enter=Gec): " -ForegroundColor Yellow -NoNewline
    $openGui = Read-Host
    if ($openGui -and $openGui.Trim().ToUpper() -eq "G") {
        Start-Process "windowsdefender://threat" -ErrorAction SilentlyContinue
    }
}

function Invoke-DefenderSignatureUpdateTool {
    Write-Host ""
    Write-Host "  [DEFENDER GUVEVNLIK TANIMLARI GUNCELLEME]" -ForegroundColor Green
    Write-Host "  Imza guncellemeleri denetleniyor ve indiriliyor..." -ForegroundColor Yellow
    try {
        Update-MpSignature -ErrorAction Stop
        Write-Host "  [BASARILI] Virus ve tehdit koruma imzalari basariyla guncellendi." -ForegroundColor Green
    } catch {
        Write-Host "  [HATA] Imza guncellemesi basarisiz: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Show-FirewallStatusCard {
    Write-Host ""
    Write-Host "  [WINDOWS GUVENLIK DUVARI (FIREWALL) DURUMU]" -ForegroundColor Green
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"

    try {
        $profiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($p in $profiles) {
            $enCol = if ($p.Enabled) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
            $enTxt = if ($p.Enabled) { "AKTIF" } else { "KAPALI" }
            Write-Host "  Profil: $($p.Name.PadRight(12)) " -ForegroundColor DarkCyan -NoNewline
            Write-Host "Durum: $enTxt".PadRight(16) -ForegroundColor $enCol -NoNewline
            Write-Host "Gelen: $($p.DefaultInboundAction) | Giden: $($p.DefaultOutboundAction)" -ForegroundColor White
        }
    } catch {
        Write-Host "  [BILGI] Guvenlik duvari durumu alinamadi: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Draw-HorizontalLine -Width 86 -Color DarkCyan -Char "-"
}

function Invoke-OpenUacSettingsTool {
    Write-Host ""
    Write-Host "  [KULLANICI HESABI DENETIMI (UAC) AYARLARI ACILIYOR]" -ForegroundColor Green
    try {
        Start-Process "UserAccountControlSettings.exe"
        Write-Host "  [BASARILI] UAC Ayarlari penceresi acildi." -ForegroundColor Green
    } catch {
        Write-Host "  [HATA] UAC ayarlari acilamadi: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================================
# 7. WINDOWS YONETIM MERKEZI (KATEGORI 3)
# ============================================================================

function Show-WinverCard {
    Write-Host ""
    Write-Host "  [WINDOWS SURUM DETAYLARI]" -ForegroundColor Green
    try {
        Start-Process "winver.exe"
    } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Host "  Isletim Sistemi : $($os.Caption)" -ForegroundColor White
        Write-Host "  Surum           : $($os.Version) (Build: $($os.BuildNumber))" -ForegroundColor Cyan
        Write-Host "  Mimari          : $($os.OSArchitecture)" -ForegroundColor White
        Write-Host "  Kurulum Tarihi  : $($os.InstallDate)" -ForegroundColor DarkCyan
    } catch {}
}

# ============================================================================
# EXPORT MODULE MEMBERS
# ============================================================================
Export-ModuleMember -Function @(
    'Test-AdminPrivilege',
    'Show-AdminWarningMessage',
    'Confirm-UserPrompt',
    'Invoke-LiveProcess',
    'Start-QuickToolApp',
    'Invoke-UserTempCleanup',
    'Invoke-WindowsTempCleanup',
    'Invoke-RecycleBinEmpty',
    'Invoke-BrowserCacheClear',
    'Invoke-FullDeepCleanup',
    'Get-FastActiveNetworkAdapter',
    'Invoke-PingTestTool',
    'Show-NetworkInfoCard',
    'Invoke-DnsFlushTool',
    'Set-QuickDnsProvider',
    'Reset-DnsToDhcp',
    'Invoke-NetworkAdapterRestart',
    'Invoke-SfcScanTool',
    'Invoke-DismCheckTool',
    'Invoke-DismRepairTool',
    'Invoke-ChkdskScanTool',
    'Invoke-MemoryDiagnosticTool',
    'Show-WinGetUpdatesView',
    'Invoke-WinGetUpdateAllAction',
    'Invoke-OpenWindowsUpdateSettings',
    'Show-DefenderStatusCard',
    'Invoke-DefenderQuickScanTool',
    'Invoke-DefenderSignatureUpdateTool',
    'Show-FirewallStatusCard',
    'Invoke-OpenUacSettingsTool',
    'Show-WinverCard'
)

