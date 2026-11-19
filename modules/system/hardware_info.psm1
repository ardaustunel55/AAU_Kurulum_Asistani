<#
.SYNOPSIS
    AAU Kurulum Asistani - Donanim & Sistem Bilgileri Modulu
.DESCRIPTION
    Islemci, RAM, GPU, Anakart/BIOS, Disk, Windows bilgilerini gosterir
    ve tum bilgileri TXT rapor olarak kaydeder.
.NOTES
    PowerShell 5.1 uyumlu. Yonetici izni gerektirmez.
#>

# ============================================================================
# YARDIMCI FONKSİYONLAR
# ============================================================================

# Loglama fonksiyonlari ana uygulamadan gelmediyse guvenli yedek olustur
if (-not (Get-Command "Write-LogInfo" -ErrorAction SilentlyContinue)) {
    function Write-LogInfo    { param([string]$m) }
    function Write-LogWarn    { param([string]$m) }
    function Write-LogError   { param([string]$m) }
    function Write-LogSuccess { param([string]$m) }
}

function Format-FileSize {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes Byte"
}

function Write-InfoLine {
    param(
        [string]$Label,
        [string]$Value,
        [ConsoleColor]$LabelColor = [ConsoleColor]::DarkCyan,
        [ConsoleColor]$ValueColor = [ConsoleColor]::White
    )
    Write-Host "    $Label" -ForegroundColor $LabelColor -NoNewline
    Write-Host "$Value" -ForegroundColor $ValueColor
}

function Write-SectionTitle {
    param([string]$Title, [ConsoleColor]$Color = [ConsoleColor]::Green)
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor $Color
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
}

function Get-SafeCimInstance {
    param([string]$ClassName, [string]$Filter = $null)
    try {
        if ($Filter) {
            return Get-CimInstance -ClassName $ClassName -Filter $Filter -ErrorAction Stop
        } else {
            return Get-CimInstance -ClassName $ClassName -ErrorAction Stop
        }
    } catch {
        try {
            if ($Filter) {
                return Get-WmiObject -Class $ClassName -Filter $Filter -ErrorAction Stop
            } else {
                return Get-WmiObject -Class $ClassName -ErrorAction Stop
            }
        } catch {
            return $null
        }
    }
}

# ============================================================================
# 1. ISLEMCI BILGILERI
# ============================================================================

function Show-CPUInfo {
    [CmdletBinding()]
    param()

    Write-LogInfo "Islemci bilgileri goruntuleniyor."
    Write-SectionTitle "ISLEMCI (CPU) BILGILERI"

    try {
        $cpus = Get-SafeCimInstance "Win32_Processor"
        if (-not $cpus) {
            Write-Host "    [!] Islemci bilgisi alinamadi." -ForegroundColor Red
            Write-LogWarn "Islemci bilgisi alinamadi."
            return
        }

        $cpuList = @($cpus)
        $idx = 0
        foreach ($cpu in $cpuList) {
            $idx++
            if ($cpuList.Count -gt 1) {
                Write-Host "    --- Islemci $idx ---" -ForegroundColor Green
            }

            $model = if ($cpu.Name) { $cpu.Name.Trim() } else { "Bilgi alinamadi" }
            $mfr   = if ($cpu.Manufacturer) { $cpu.Manufacturer } else { "Bilgi alinamadi" }
            $cores  = if ($cpu.NumberOfCores) { $cpu.NumberOfCores.ToString() } else { "Bilgi alinamadi" }
            $logical = if ($cpu.NumberOfLogicalProcessors) { $cpu.NumberOfLogicalProcessors.ToString() } else { "Bilgi alinamadi" }
            $speed = if ($cpu.MaxClockSpeed) { "{0:N0} MHz ({1:N2} GHz)" -f $cpu.MaxClockSpeed, ($cpu.MaxClockSpeed / 1000) } else { "Bilgi alinamadi" }

            # Anlık kullanım yüzdesi
            $usage = "Bilgi alinamadi"
            try {
                $load = $cpu.LoadPercentage
                if ($null -ne $load) {
                    $usage = "%$load"
                }
            } catch {}

            # Socket bilgisi
            $socket = if ($cpu.SocketDesignation) { $cpu.SocketDesignation } else { "Bilgi alinamadi" }

            Write-InfoLine "Model             : " $model
            Write-InfoLine "Uretici           : " $mfr
            Write-InfoLine "Fiziksel Cekirdek  : " $cores
            Write-InfoLine "Mantiksal Islemci  : " $logical
            Write-InfoLine "Maks Frekans       : " $speed
            Write-InfoLine "Anlik Kullanim     : " $usage
            Write-InfoLine "Soket              : " $socket
        }
        Write-LogSuccess "Islemci bilgileri basariyla goruntulendi."
    } catch {
        Write-Host "    [HATA] Islemci bilgisi alinirken hata: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogError "Islemci bilgisi hatasi: $($_.Exception.Message)"
    }
}

# ============================================================================
# 2. RAM BILGILERI
# ============================================================================

function Show-RAMInfo {
    [CmdletBinding()]
    param()

    Write-LogInfo "RAM bilgileri goruntuleniyor."
    Write-SectionTitle "BELLEK (RAM) BILGILERI"

    try {
        $os = Get-SafeCimInstance "Win32_OperatingSystem"
        if ($os) {
            $totalKB = $os.TotalVisibleMemorySize
            $freeKB  = $os.FreePhysicalMemory
            $usedKB  = $totalKB - $freeKB
            $pct     = [math]::Round(($usedKB / $totalKB) * 100, 1)

            Write-InfoLine "Toplam RAM         : " (Format-FileSize ($totalKB * 1KB))
            Write-InfoLine "Kullanilan         : " (Format-FileSize ($usedKB * 1KB))
            Write-InfoLine "Bos                : " (Format-FileSize ($freeKB * 1KB))

            # Kullanım çubuğu
            $barLen = 30
            $filled = [math]::Round($barLen * $pct / 100)
            if ($filled -gt $barLen) { $filled = $barLen }
            $empty  = $barLen - $filled
            $bar = "[" + ("█" * $filled) + ("░" * $empty) + "]"

            $pctColor = if ($pct -ge 90) { [ConsoleColor]::Red }
                        elseif ($pct -ge 70) { [ConsoleColor]::Cyan }
                        else { [ConsoleColor]::Green }

            Write-Host "    Kullanim           : " -ForegroundColor DarkCyan -NoNewline
            Write-Host "$bar %$pct" -ForegroundColor $pctColor
        } else {
            Write-Host "    [!] Genel RAM bilgisi alinamadi." -ForegroundColor Red
        }

        # Fiziksel bellek modülleri
        $sticks = Get-SafeCimInstance "Win32_PhysicalMemory"
        if ($sticks) {
            Write-Host ""
            Write-Host "    FIZIKSEL BELLEK MODULLERI:" -ForegroundColor Green
            Write-Host ("    " + ("-" * 56)) -ForegroundColor DarkCyan
            $stickList = @($sticks)
            $slotNum = 0
            foreach ($s in $stickList) {
                $slotNum++
                $cap    = if ($s.Capacity) { Format-FileSize ([double]$s.Capacity) } else { "Bilgi alinamadi" }
                $spd    = if ($s.Speed) { "$($s.Speed) MHz" } else { "Bilgi alinamadi" }
                $mfr    = if ($s.Manufacturer -and $s.Manufacturer -ne "") { $s.Manufacturer } else { "Bilgi alinamadi" }
                $loc    = if ($s.DeviceLocator) { $s.DeviceLocator } else { "Slot $slotNum" }
                $memType = "Bilgi alinamadi"
                if ($s.SMBIOSMemoryType) {
                    switch ($s.SMBIOSMemoryType) {
                        20 { $memType = "DDR"   }
                        21 { $memType = "DDR2"  }
                        22 { $memType = "DDR2 (FB-DIMM)" }
                        24 { $memType = "DDR3"  }
                        26 { $memType = "DDR4"  }
                        30 { $memType = "LPDDR4" }
                        34 { $memType = "DDR5"  }
                        35 { $memType = "LPDDR5" }
                        default { $memType = "Tur: $($s.SMBIOSMemoryType)" }
                    }
                }

                Write-Host "    Slot $slotNum ($loc):" -ForegroundColor Green
                Write-InfoLine "      Kapasite     : " $cap
                Write-InfoLine "      Hiz          : " $spd
                Write-InfoLine "      Uretici      : " $mfr
                Write-InfoLine "      Tur           : " $memType
            }
        }
        Write-LogSuccess "RAM bilgileri basariyla goruntulendi."
    } catch {
        Write-Host "    [HATA] RAM bilgisi alinirken hata: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogError "RAM bilgisi hatasi: $($_.Exception.Message)"
    }
}

# ============================================================================
# 3. EKRAN KARTI BILGILERI
# ============================================================================

function Show-GPUInfo {
    [CmdletBinding()]
    param()

    Write-LogInfo "Ekran karti bilgileri goruntuleniyor."
    Write-SectionTitle "EKRAN KARTI (GPU) BILGILERI"

    try {
        $gpus = Get-SafeCimInstance "Win32_VideoController"
        if (-not $gpus) {
            Write-Host "    [!] Ekran karti bilgisi alinamadi." -ForegroundColor Red
            Write-LogWarn "Ekran karti bilgisi alinamadi."
            return
        }

        $gpuList = @($gpus)
        $idx = 0
        foreach ($gpu in $gpuList) {
            $idx++
            if ($gpuList.Count -gt 1) {
                Write-Host "    --- Ekran Karti $idx ---" -ForegroundColor Green
            }

            $name  = if ($gpu.Name) { $gpu.Name } else { "Bilgi alinamadi" }
            $mfr   = if ($gpu.AdapterCompatibility) { $gpu.AdapterCompatibility } else { "Bilgi alinamadi" }
            $driver = if ($gpu.DriverVersion) { $gpu.DriverVersion } else { "Bilgi alinamadi" }
            $driverDate = "Bilgi alinamadi"
            try {
                if ($gpu.DriverDate) {
                    $driverDate = ([System.Management.ManagementDateTimeConverter]::ToDateTime($gpu.DriverDate.ToString())).ToString("yyyy-MM-dd")
                }
            } catch {
                try {
                    if ($gpu.DriverDate -is [DateTime]) { $driverDate = $gpu.DriverDate.ToString("yyyy-MM-dd") }
                } catch {}
            }

            $resolution = "Bilgi alinamadi"
            try {
                if ($gpu.CurrentHorizontalResolution -and $gpu.CurrentVerticalResolution) {
                    $resolution = "$($gpu.CurrentHorizontalResolution) x $($gpu.CurrentVerticalResolution)"
                    if ($gpu.CurrentRefreshRate) { $resolution += " @ $($gpu.CurrentRefreshRate)Hz" }
                }
            } catch {}

            # VRAM - WMI uint32 sınırı nedeniyle 4GB'dan büyük değerleri doğru gösteremeyebilir
            $vram = "Bilgi alinamadi"
            try {
                if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                    $vramBytes = [double]$gpu.AdapterRAM
                    # Uint32 taşması kontrolü (negatif veya çok küçük = büyük kart)
                    if ($vramBytes -lt 0) {
                        $vramBytes = 4GB + (4GB + $vramBytes)
                    }
                    $vram = Format-FileSize $vramBytes
                }
            } catch {}

            $status = if ($gpu.Status) { $gpu.Status } else { "Bilgi alinamadi" }

            Write-InfoLine "Model              : " $name
            Write-InfoLine "Uretici            : " $mfr
            Write-InfoLine "Video Bellegi (VRAM): " $vram
            Write-InfoLine "Surucu Surumu       : " $driver
            Write-InfoLine "Surucu Tarihi       : " $driverDate
            Write-InfoLine "Cozunurluk          : " $resolution
            Write-InfoLine "Durum               : " $status
            Write-Host ""
        }
        Write-LogSuccess "Ekran karti bilgileri basariyla goruntulendi."
    } catch {
        Write-Host "    [HATA] Ekran karti bilgisi alinirken hata: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogError "Ekran karti bilgisi hatasi: $($_.Exception.Message)"
    }
}

# ============================================================================
# 4. ANAKART VE BIOS BILGILERI
# ============================================================================

function Show-MotherboardBIOSInfo {
    [CmdletBinding()]
    param()

    Write-LogInfo "Anakart ve BIOS bilgileri goruntuleniyor."
    Write-SectionTitle "ANAKART VE BIOS BILGILERI"

    try {
        # Anakart bilgileri
        $board = Get-SafeCimInstance "Win32_BaseBoard"
        Write-Host "    ANAKART:" -ForegroundColor Green
        if ($board) {
            $boardList = @($board)
            $b = $boardList[0]
            $bmfr    = if ($b.Manufacturer) { $b.Manufacturer } else { "Bilgi alinamadi" }
            $bmodel  = if ($b.Product) { $b.Product } else { "Bilgi alinamadi" }
            $bserial = if ($b.SerialNumber -and $b.SerialNumber -ne "To Be Filled By O.E.M.") { $b.SerialNumber } else { "Bilgi alinamadi" }

            Write-InfoLine "      Uretici      : " $bmfr
            Write-InfoLine "      Model        : " $bmodel
            Write-InfoLine "      Seri No      : " $bserial
        } else {
            Write-Host "      [!] Anakart bilgisi alinamadi." -ForegroundColor Red
        }

        Write-Host ""

        # BIOS bilgileri
        $bios = Get-SafeCimInstance "Win32_BIOS"
        Write-Host "    BIOS:" -ForegroundColor Green
        if ($bios) {
            $biosList = @($bios)
            $bi = $biosList[0]
            $bver  = if ($bi.SMBIOSBIOSVersion) { $bi.SMBIOSBIOSVersion } else { "Bilgi alinamadi" }
            $bmfr2 = if ($bi.Manufacturer) { $bi.Manufacturer } else { "Bilgi alinamadi" }

            $bdate = "Bilgi alinamadi"
            try {
                if ($bi.ReleaseDate) {
                    $bdate = ([System.Management.ManagementDateTimeConverter]::ToDateTime($bi.ReleaseDate.ToString())).ToString("yyyy-MM-dd")
                }
            } catch {
                try {
                    if ($bi.ReleaseDate -is [DateTime]) { $bdate = $bi.ReleaseDate.ToString("yyyy-MM-dd") }
                } catch {}
            }

            Write-InfoLine "      Surum        : " $bver
            Write-InfoLine "      Uretici      : " $bmfr2
            Write-InfoLine "      Tarih        : " $bdate
        } else {
            Write-Host "      [!] BIOS bilgisi alinamadi." -ForegroundColor Red
        }

        # UEFI / Legacy tespiti
        Write-Host ""
        Write-Host "    FIRMWARE MODU:" -ForegroundColor Green
        $fwMode = "Bilgi alinamadi"
        try {
            # Yöntem 1: Ortam değişkeni
            $fwType = $env:firmware_type
            if ($fwType) {
                $fwMode = $fwType
            }
        } catch {}

        if ($fwMode -eq "Bilgi alinamadi") {
            try {
                # Yöntem 2: SecureBoot registry kontrolü
                $sb = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction Stop
                if ($null -ne $sb.UEFISecureBootEnabled) {
                    $fwMode = "UEFI (Secure Boot Aktif)"
                }
            } catch {
                try {
                    # Yöntem 3: EFI sistem bölümü kontrolü
                    $efi = Get-Partition -ErrorAction Stop | Where-Object { $_.GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" }
                    if ($efi) { $fwMode = "UEFI" } else { $fwMode = "Legacy (BIOS)" }
                } catch {
                    $fwMode = "Bilgi alinamadi"
                }
            }
        }
        Write-InfoLine "      Mod          : " $fwMode

        Write-LogSuccess "Anakart ve BIOS bilgileri basariyla goruntulendi."
    } catch {
        Write-Host "    [HATA] Anakart/BIOS bilgisi alinirken hata: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogError "Anakart/BIOS bilgisi hatasi: $($_.Exception.Message)"
    }
}

# ============================================================================
# 5. DISK BILGILERI
# ============================================================================

function Show-DiskInfo {
    [CmdletBinding()]
    param()

    Write-LogInfo "Disk bilgileri goruntuleniyor."
    Write-SectionTitle "DISK VE BOLUMLENDIRME BILGILERI"

    try {
        # Fiziksel diskler
        $physDisks = Get-SafeCimInstance "Win32_DiskDrive"
        if ($physDisks) {
            Write-Host "    FIZIKSEL DISKLER:" -ForegroundColor Green
            Write-Host ("    " + ("-" * 56)) -ForegroundColor DarkCyan
            $pdList = @($physDisks)
            foreach ($pd in $pdList) {
                $dModel  = if ($pd.Model) { $pd.Model } else { "Bilgi alinamadi" }
                $dSize   = if ($pd.Size) { Format-FileSize ([double]$pd.Size) } else { "Bilgi alinamadi" }
                $dType   = if ($pd.MediaType) { $pd.MediaType } else { "Bilgi alinamadi" }
                $dIF     = if ($pd.InterfaceType) { $pd.InterfaceType } else { "Bilgi alinamadi" }

                Write-InfoLine "    Model          : " $dModel
                Write-InfoLine "    Kapasite       : " $dSize
                Write-InfoLine "    Ortam Turu     : " $dType
                Write-InfoLine "    Arayuz         : " $dIF
                Write-Host ""
            }
        }

        # Mantıksal sürücüler (yerel sabit diskler)
        $logDisks = Get-SafeCimInstance "Win32_LogicalDisk" "DriveType=3"
        if ($logDisks) {
            Write-Host "    MANTIKSAL SURUCULER (BOLUMLER):" -ForegroundColor Green
            Write-Host ("    " + ("-" * 56)) -ForegroundColor DarkCyan

            $ldList = @($logDisks)
            foreach ($ld in $ldList) {
                $devID  = if ($ld.DeviceID) { $ld.DeviceID } else { "?" }
                $volName = if ($ld.VolumeName) { $ld.VolumeName } else { "(Adsiz)" }
                $fs     = if ($ld.FileSystem) { $ld.FileSystem } else { "Bilgi alinamadi" }

                $totalSize = 0; $freeSize = 0; $usedSize = 0; $pct = 0
                if ($ld.Size -and $ld.FreeSpace) {
                    $totalSize = [double]$ld.Size
                    $freeSize  = [double]$ld.FreeSpace
                    $usedSize  = $totalSize - $freeSize
                    if ($totalSize -gt 0) { $pct = [math]::Round(($usedSize / $totalSize) * 100, 1) }
                }

                # Kullanım çubuğu
                $barLen = 25
                $filled = [math]::Round($barLen * $pct / 100)
                if ($filled -gt $barLen) { $filled = $barLen }
                $empty  = $barLen - $filled
                $bar = "[" + ("█" * $filled) + ("░" * $empty) + "]"

                $barColor = if ($pct -ge 90) { [ConsoleColor]::Red }
                            elseif ($pct -ge 70) { [ConsoleColor]::Cyan }
                            else { [ConsoleColor]::Green }

                Write-Host "    Surucu $devID ($volName)" -ForegroundColor Green
                Write-InfoLine "      Dosya Sistemi : " $fs
                Write-InfoLine "      Toplam        : " (Format-FileSize $totalSize)
                Write-InfoLine "      Kullanilan     : " (Format-FileSize $usedSize)
                Write-InfoLine "      Bos            : " (Format-FileSize $freeSize)
                Write-Host "      Kullanim       : " -ForegroundColor DarkCyan -NoNewline
                Write-Host "$bar %$pct" -ForegroundColor $barColor
                Write-Host ""
            }
        } else {
            Write-Host "    [!] Mantiksal surucu bilgisi alinamadi." -ForegroundColor Red
        }

        Write-LogSuccess "Disk bilgileri basariyla goruntulendi."
    } catch {
        Write-Host "    [HATA] Disk bilgisi alinirken hata: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogError "Disk bilgisi hatasi: $($_.Exception.Message)"
    }
}

# ============================================================================
# 6. WINDOWS BILGILERI
# ============================================================================

function Show-WindowsInfo {
    [CmdletBinding()]
    param()

    Write-LogInfo "Windows bilgileri goruntuleniyor."
    Write-SectionTitle "WINDOWS ISLETIM SISTEMI BILGILERI"

    try {
        $os = Get-SafeCimInstance "Win32_OperatingSystem"
        $cs = Get-SafeCimInstance "Win32_ComputerSystem"

        if ($os) {
            $caption = if ($os.Caption) { $os.Caption.Trim() } else { "Bilgi alinamadi" }
            $build   = if ($os.BuildNumber) { $os.BuildNumber } else { "Bilgi alinamadi" }
            $arch    = if ($os.OSArchitecture) { $os.OSArchitecture } else { "Bilgi alinamadi" }
            $ver     = if ($os.Version) { $os.Version } else { "Bilgi alinamadi" }

            # Kurulum tarihi
            $installDate = "Bilgi alinamadi"
            try {
                if ($os.InstallDate) {
                    if ($os.InstallDate -is [DateTime]) {
                        $installDate = $os.InstallDate.ToString("yyyy-MM-dd HH:mm:ss")
                    } else {
                        $installDate = ([System.Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate.ToString())).ToString("yyyy-MM-dd HH:mm:ss")
                    }
                }
            } catch {}

            # Son önyükleme
            $lastBoot = "Bilgi alinamadi"
            try {
                if ($os.LastBootUpTime) {
                    $bootTime = $null
                    if ($os.LastBootUpTime -is [DateTime]) {
                        $bootTime = $os.LastBootUpTime
                    } else {
                        $bootTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime.ToString())
                    }
                    if ($bootTime) {
                        $uptime = (Get-Date) - $bootTime
                        $lastBoot = "$($bootTime.ToString('yyyy-MM-dd HH:mm:ss'))  (Calisma: $([math]::Floor($uptime.TotalDays)) gun $($uptime.Hours) saat)"
                    }
                }
            } catch {}

            Write-InfoLine "Isletim Sistemi    : " $caption
            Write-InfoLine "Surum              : " $ver
            Write-InfoLine "Derleme (Build)    : " $build
            Write-InfoLine "Mimari             : " $arch
            Write-InfoLine "Kurulum Tarihi     : " $installDate
            Write-InfoLine "Son Onyukleme      : " $lastBoot
        } else {
            Write-Host "    [!] Windows bilgisi alinamadi." -ForegroundColor Red
        }

        # Bilgisayar bilgileri
        Write-Host ""
        $pcName = $env:COMPUTERNAME
        if (-not $pcName) { $pcName = "Bilgi alinamadi" }
        $userName = $env:USERNAME
        if (-not $userName) { $userName = "Bilgi alinamadi" }
        $domain = if ($cs -and $cs.Domain) { $cs.Domain } else { $env:USERDOMAIN }
        if (-not $domain) { $domain = "Bilgi alinamadi" }

        $sysModel = "Bilgi alinamadi"
        $sysMfr   = "Bilgi alinamadi"
        if ($cs) {
            if ($cs.Model) { $sysModel = $cs.Model }
            if ($cs.Manufacturer) { $sysMfr = $cs.Manufacturer }
        }

        Write-InfoLine "Bilgisayar Adi     : " $pcName
        Write-InfoLine "Kullanici Adi      : " $userName
        Write-InfoLine "Etki Alani         : " $domain
        Write-InfoLine "Sistem Uretici     : " $sysMfr
        Write-InfoLine "Sistem Modeli      : " $sysModel

        Write-LogSuccess "Windows bilgileri basariyla goruntulendi."
    } catch {
        Write-Host "    [HATA] Windows bilgisi alinirken hata: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogError "Windows bilgisi hatasi: $($_.Exception.Message)"
    }
}

# ============================================================================
# 7. SISTEM RAPORU OLUSTURMA
# ============================================================================

function New-SystemReport {
    [CmdletBinding()]
    param()

    Write-LogInfo "Sistem raporu olusturuluyor."
    Write-SectionTitle "SISTEM RAPORU OLUSTURULUYOR..."

    try {
        $reportLines = @()
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $reportLines += "=" * 70
        $reportLines += "  AAU KURULUM ASISTANI - SISTEM RAPORU"
        $reportLines += "  Olusturma Tarihi: $ts"
        $reportLines += "=" * 70
        $reportLines += ""

        # ---------- İŞLEMCİ ----------
        $reportLines += "-" * 70
        $reportLines += "  ISLEMCI (CPU) BILGILERI"
        $reportLines += "-" * 70
        try {
            $cpus = Get-SafeCimInstance "Win32_Processor"
            if ($cpus) {
                $cpuList = @($cpus)
                foreach ($cpu in $cpuList) {
                    $reportLines += "  Model             : $(if ($cpu.Name) { $cpu.Name.Trim() } else { 'Bilgi alinamadi' })"
                    $reportLines += "  Uretici           : $(if ($cpu.Manufacturer) { $cpu.Manufacturer } else { 'Bilgi alinamadi' })"
                    $reportLines += "  Fiziksel Cekirdek  : $(if ($cpu.NumberOfCores) { $cpu.NumberOfCores } else { 'Bilgi alinamadi' })"
                    $reportLines += "  Mantiksal Islemci  : $(if ($cpu.NumberOfLogicalProcessors) { $cpu.NumberOfLogicalProcessors } else { 'Bilgi alinamadi' })"
                    $speed = if ($cpu.MaxClockSpeed) { "{0:N0} MHz ({1:N2} GHz)" -f $cpu.MaxClockSpeed, ($cpu.MaxClockSpeed / 1000) } else { "Bilgi alinamadi" }
                    $reportLines += "  Maks Frekans       : $speed"
                    $loadStr = if ($null -ne $cpu.LoadPercentage) { "%$($cpu.LoadPercentage)" } else { "Bilgi alinamadi" }
                    $reportLines += "  Anlik Kullanim     : $loadStr"
                }
            } else { $reportLines += "  Bilgi alinamadi." }
        } catch { $reportLines += "  Hata: $($_.Exception.Message)" }
        $reportLines += ""

        # ---------- RAM ----------
        $reportLines += "-" * 70
        $reportLines += "  BELLEK (RAM) BILGILERI"
        $reportLines += "-" * 70
        try {
            $os = Get-SafeCimInstance "Win32_OperatingSystem"
            if ($os) {
                $totalKB = $os.TotalVisibleMemorySize; $freeKB = $os.FreePhysicalMemory; $usedKB = $totalKB - $freeKB
                $pct = [math]::Round(($usedKB / $totalKB) * 100, 1)
                $reportLines += "  Toplam RAM         : $(Format-FileSize ($totalKB * 1KB))"
                $reportLines += "  Kullanilan         : $(Format-FileSize ($usedKB * 1KB))"
                $reportLines += "  Bos                : $(Format-FileSize ($freeKB * 1KB))"
                $reportLines += "  Kullanim           : %$pct"
            } else { $reportLines += "  Bilgi alinamadi." }

            $sticks = Get-SafeCimInstance "Win32_PhysicalMemory"
            if ($sticks) {
                $stickList = @($sticks)
                $slotNum = 0
                foreach ($s in $stickList) {
                    $slotNum++
                    $cap = if ($s.Capacity) { Format-FileSize ([double]$s.Capacity) } else { "Bilgi alinamadi" }
                    $spd = if ($s.Speed) { "$($s.Speed) MHz" } else { "Bilgi alinamadi" }
                    $reportLines += "  Slot $slotNum             : $cap @ $spd"
                }
            }
        } catch { $reportLines += "  Hata: $($_.Exception.Message)" }
        $reportLines += ""

        # ---------- EKRAN KARTI ----------
        $reportLines += "-" * 70
        $reportLines += "  EKRAN KARTI (GPU) BILGILERI"
        $reportLines += "-" * 70
        try {
            $gpus = Get-SafeCimInstance "Win32_VideoController"
            if ($gpus) {
                $gpuList = @($gpus)
                foreach ($gpu in $gpuList) {
                    $reportLines += "  Model              : $(if ($gpu.Name) { $gpu.Name } else { 'Bilgi alinamadi' })"
                    $reportLines += "  Uretici            : $(if ($gpu.AdapterCompatibility) { $gpu.AdapterCompatibility } else { 'Bilgi alinamadi' })"
                    $vram = "Bilgi alinamadi"
                    try {
                        if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                            $vramBytes = [double]$gpu.AdapterRAM
                            if ($vramBytes -lt 0) { $vramBytes = 4GB + (4GB + $vramBytes) }
                            $vram = Format-FileSize $vramBytes
                        }
                    } catch {}
                    $reportLines += "  Video Bellegi      : $vram"
                    $reportLines += ""
                }
            } else { $reportLines += "  Bilgi alinamadi." }
        } catch { $reportLines += "  Hata: $($_.Exception.Message)" }
        $reportLines += ""

        # ---------- ANAKART & BIOS ----------
        $reportLines += "-" * 70
        $reportLines += "  ANAKART VE BIOS BILGILERI"
        $reportLines += "-" * 70
        try {
            $board = Get-SafeCimInstance "Win32_BaseBoard"
            if ($board) {
                $bl = @($board)
                $b = $bl[0]
                $reportLines += "  Anakart Uretici    : $(if ($b.Manufacturer) { $b.Manufacturer } else { 'Bilgi alinamadi' })"
                $reportLines += "  Anakart Model      : $(if ($b.Product) { $b.Product } else { 'Bilgi alinamadi' })"
            } else { $reportLines += "  Anakart bilgisi alinamadi." }

            $bios = Get-SafeCimInstance "Win32_BIOS"
            if ($bios) {
                $bl2 = @($bios)
                $bi = $bl2[0]
                $reportLines += "  BIOS Surum         : $(if ($bi.SMBIOSBIOSVersion) { $bi.SMBIOSBIOSVersion } else { 'Bilgi alinamadi' })"
                $reportLines += "  BIOS Uretici       : $(if ($bi.Manufacturer) { $bi.Manufacturer } else { 'Bilgi alinamadi' })"
                $bdate = "Bilgi alinamadi"
                try {
                    if ($bi.ReleaseDate) {
                        $bdate = ([System.Management.ManagementDateTimeConverter]::ToDateTime($bi.ReleaseDate.ToString())).ToString("yyyy-MM-dd")
                    }
                } catch {
                    try {
                        if ($bi.ReleaseDate -is [DateTime]) { $bdate = $bi.ReleaseDate.ToString("yyyy-MM-dd") }
                    } catch {}
                }
                $reportLines += "  BIOS Tarihi        : $bdate"
            }

            # Firmware modu
            $fwMode = "Bilgi alinamadi"
            try {
                $fwType = $env:firmware_type
                if ($fwType) { $fwMode = $fwType }
            } catch {}
            if ($fwMode -eq "Bilgi alinamadi") {
                try {
                    $sb = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -ErrorAction Stop
                    if ($null -ne $sb.UEFISecureBootEnabled) { $fwMode = "UEFI" }
                } catch {}
            }
            $reportLines += "  Firmware Modu      : $fwMode"
        } catch { $reportLines += "  Hata: $($_.Exception.Message)" }
        $reportLines += ""

        # ---------- DİSKLER ----------
        $reportLines += "-" * 70
        $reportLines += "  DISK BILGILERI"
        $reportLines += "-" * 70
        try {
            $logDisks = Get-SafeCimInstance "Win32_LogicalDisk" "DriveType=3"
            if ($logDisks) {
                $ldList = @($logDisks)
                foreach ($ld in $ldList) {
                    $devID  = if ($ld.DeviceID) { $ld.DeviceID } else { "?" }
                    $volName = if ($ld.VolumeName) { $ld.VolumeName } else { "(Adsiz)" }
                    $fs     = if ($ld.FileSystem) { $ld.FileSystem } else { "Bilgi alinamadi" }
                    $total = 0; $free = 0; $used = 0; $pct = 0
                    if ($ld.Size -and $ld.FreeSpace) {
                        $total = [double]$ld.Size; $free = [double]$ld.FreeSpace; $used = $total - $free
                        if ($total -gt 0) { $pct = [math]::Round(($used / $total) * 100, 1) }
                    }
                    $reportLines += "  Surucu $devID ($volName)"
                    $reportLines += "    Dosya Sistemi   : $fs"
                    $reportLines += "    Toplam          : $(Format-FileSize $total)"
                    $reportLines += "    Kullanilan       : $(Format-FileSize $used)"
                    $reportLines += "    Bos              : $(Format-FileSize $free)"
                    $reportLines += "    Kullanim         : %$pct"
                    $reportLines += ""
                }
            } else { $reportLines += "  Bilgi alinamadi." }
        } catch { $reportLines += "  Hata: $($_.Exception.Message)" }
        $reportLines += ""

        # ---------- WINDOWS ----------
        $reportLines += "-" * 70
        $reportLines += "  WINDOWS BILGILERI"
        $reportLines += "-" * 70
        try {
            $os2 = Get-SafeCimInstance "Win32_OperatingSystem"
            $cs2 = Get-SafeCimInstance "Win32_ComputerSystem"
            if ($os2) {
                $reportLines += "  Isletim Sistemi    : $(if ($os2.Caption) { $os2.Caption.Trim() } else { 'Bilgi alinamadi' })"
                $reportLines += "  Surum              : $(if ($os2.Version) { $os2.Version } else { 'Bilgi alinamadi' })"
                $reportLines += "  Derleme (Build)    : $(if ($os2.BuildNumber) { $os2.BuildNumber } else { 'Bilgi alinamadi' })"
                $reportLines += "  Mimari             : $(if ($os2.OSArchitecture) { $os2.OSArchitecture } else { 'Bilgi alinamadi' })"
                $instDate = "Bilgi alinamadi"
                try {
                    if ($os2.InstallDate) {
                        if ($os2.InstallDate -is [DateTime]) { $instDate = $os2.InstallDate.ToString("yyyy-MM-dd HH:mm:ss") }
                        else { $instDate = ([System.Management.ManagementDateTimeConverter]::ToDateTime($os2.InstallDate.ToString())).ToString("yyyy-MM-dd HH:mm:ss") }
                    }
                } catch {}
                $reportLines += "  Kurulum Tarihi     : $instDate"
            }
            $reportLines += "  Bilgisayar Adi     : $(if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'Bilgi alinamadi' })"
            $reportLines += "  Kullanici Adi      : $(if ($env:USERNAME) { $env:USERNAME } else { 'Bilgi alinamadi' })"
            if ($cs2) {
                $reportLines += "  Sistem Uretici     : $(if ($cs2.Manufacturer) { $cs2.Manufacturer } else { 'Bilgi alinamadi' })"
                $reportLines += "  Sistem Modeli      : $(if ($cs2.Model) { $cs2.Model } else { 'Bilgi alinamadi' })"
            }
        } catch { $reportLines += "  Hata: $($_.Exception.Message)" }
        $reportLines += ""

        $reportLines += "=" * 70
        $reportLines += "  Rapor Sonu - AAU Kurulum Asistani v2.0.0"
        $reportLines += "=" * 70

        # Dosyaya kaydet
        $reportsDir = $null
        try {
            # $script:ProjectRoot modülde erişilemeyebilir, alternatif yol bul
            $projRoot = $null

            # Yöntem 1: Script scope variable
            if ($script:ProjectRoot -and (Test-Path $script:ProjectRoot)) {
                $projRoot = $script:ProjectRoot
            }

            # Yöntem 2: Global variable
            if (-not $projRoot) {
                $gRoot = Get-Variable -Name "ProjectRoot" -Scope Global -ValueOnly -ErrorAction SilentlyContinue
                if ($gRoot -and (Test-Path $gRoot)) { $projRoot = $gRoot }
            }

            # Yöntem 3: Modül konumundan türet
            if (-not $projRoot) {
                $modPath = $PSScriptRoot
                if ($modPath) {
                    $projRoot = Split-Path (Split-Path $modPath -Parent) -Parent
                }
            }

            # Yöntem 4: Masaüstü fallback
            if (-not $projRoot -or -not (Test-Path $projRoot)) {
                $projRoot = Join-Path $env:USERPROFILE "Desktop\AAU_Kurulum_Asistani"
            }

            $reportsDir = Join-Path $projRoot "reports"
            if (-not (Test-Path $reportsDir)) {
                $null = New-Item $reportsDir -ItemType Directory -Force
            }
        } catch {
            $reportsDir = Join-Path $env:USERPROFILE "Desktop"
        }

        $fileTs = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportPath = Join-Path $reportsDir "SistemRaporu_$fileTs.txt"

        $reportLines | Out-File -FilePath $reportPath -Encoding UTF8 -Force

        Write-Host ""
        Write-Host "    [BASARILI] Sistem raporu basariyla olusturuldu!" -ForegroundColor Green
        Write-Host ""
        Write-InfoLine "    Dosya Yolu     : " $reportPath
        Write-InfoLine "    Dosya Boyutu   : " (Format-FileSize (Get-Item $reportPath).Length)
        Write-Host ""
        Write-Host "    Raporu acmak icin: " -ForegroundColor DarkCyan -NoNewline
        Write-Host "notepad `"$reportPath`"" -ForegroundColor White

        Write-LogSuccess "Sistem raporu olusturuldu: $reportPath"
    } catch {
        Write-Host "    [HATA] Rapor olusturulurken hata: $($_.Exception.Message)" -ForegroundColor Red
        Write-LogError "Sistem raporu hatasi: $($_.Exception.Message)"
    }
}

# ============================================================================
# MODUL DISA AKTARMA
# ============================================================================

Export-ModuleMember -Function @(
    'Show-CPUInfo',
    'Show-RAMInfo',
    'Show-GPUInfo',
    'Show-MotherboardBIOSInfo',
    'Show-DiskInfo',
    'Show-WindowsInfo',
    'New-SystemReport',
    'Format-FileSize',
    'Write-InfoLine',
    'Write-SectionTitle',
    'Get-SafeCimInstance'
)
