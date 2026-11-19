#Requires -Version 5.1
<#
.SYNOPSIS
    AAU Kurulum Asistani - Admin Cekirdek Modulu
.DESCRIPTION
    Ortak veri giris fonksiyonlari, JSON dosya yonetimi ve AAU konsol tasarim
    bilesenlerini icerir. PowerShell 5.1 uyumlu. Tum moduller bu modulu temel alir.
.NOTES
    Surum      : 1.0.0
    PowerShell : 5.1+
    Bagimlilık : $script:ProjectRoot, $script:DataDir, $script:LogFilePath (optional)
#>

Set-StrictMode -Version Latest

# ==============================================================================
# BOLUM 1: ORTAK YARDIMCI
# ==============================================================================

function script:Get-DataDirectory {
    if ($script:DataDir -and (Test-Path $script:DataDir)) { return $script:DataDir }
    $root = if ($script:ProjectRoot) { $script:ProjectRoot } else { (Get-Location).Path }
    return Join-Path $root 'data'
}

function script:Get-BackupsDirectory {
    $backupsDir = Join-Path (script:Get-DataDirectory) 'backups'
    if (-not (Test-Path $backupsDir)) {
        $null = New-Item -Path $backupsDir -ItemType Directory -Force -ErrorAction SilentlyContinue
    }
    return $backupsDir
}

function script:Write-ModuleLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $logPath = if ($script:LogFilePath -and (Test-Path $script:LogFilePath)) { $script:LogFilePath }
                   elseif ($global:LogFilePath -and (Test-Path $global:LogFilePath)) { $global:LogFilePath }
                   else { $null }
        if ($logPath) {
            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Add-Content -Path $logPath -Value "[$ts] [$Level] [admin_core] $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch {}
}

# ==============================================================================
# BOLUM 2: ORTAK VERİ GİRİŞ FONKSİYONLARI
# ==============================================================================

function Read-UserText {
<#
.SYNOPSIS
    Kullanicidan metin girisi alir.
.DESCRIPTION
    Bos gecilebilinir. Varsayilan deger gosterilir. 0 girisi iptal anlamina gelir.
    $null doner -> iptal; "" doner -> bos / varsayilan kabul edildi; string doner -> giris
.PARAMETER Prompt
    Kullaniciya gosterilecek istem metni.
.PARAMETER DefaultValue
    Bos Enter basildiginda kullanilacak varsayilan deger.
.PARAMETER AllowEmpty
    Bos girise izin verir (varsayilan: $true)
.PARAMETER MaxLength
    Maksimum karakter sayisi (0 = sinir yok)
.EXAMPLE
    $ad = Read-UserText -Prompt "Uygulama adi" -DefaultValue "Varsayilan"
#>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$DefaultValue = '',
        [bool]$AllowEmpty = $true,
        [int]$MaxLength = 0
    )

    while ($true) {
        $display = if ($DefaultValue -ne '') { " [Varsayilan: $DefaultValue]" } else { '' }
        $cancelHint = if ($AllowEmpty) { ' (0=Iptal)' } else { ' (0=Iptal)' }
        Write-Host "  $Prompt$display$cancelHint : " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host

        if ($null -eq $inp) { $inp = '' }
        $inp = $inp.Trim()

        if ($inp -eq '0') { return $null }   # iptal

        if ($inp -eq '' -and $DefaultValue -ne '') {
            return $DefaultValue               # varsayilan kabul
        }

        if ($inp -eq '' -and $AllowEmpty) {
            return ''                          # bos kabul
        }

        if ($inp -eq '' -and -not $AllowEmpty) {
            Write-Host '  [UYARI] Bu alan bos birakilamaz.' -ForegroundColor Yellow
            continue
        }

        if ($MaxLength -gt 0 -and $inp.Length -gt $MaxLength) {
            Write-Host "  [UYARI] En fazla $MaxLength karakter girebilirsiniz." -ForegroundColor Yellow
            continue
        }

        return $inp
    }
}

function Read-UserNumber {
<#
.SYNOPSIS
    Kullanicidan sayisal deger alir, min/max dogrular. 0 = iptal.
.PARAMETER Prompt
    Kullaniciya gosterilecek istem.
.PARAMETER MinValue
    Kabul edilecek minimum deger.
.PARAMETER MaxValue
    Kabul edilecek maksimum deger.
.PARAMETER DefaultValue
    Bos Enter basildiginda kullanilacak varsayilan (opsiyonel).
.EXAMPLE
    $port = Read-UserNumber -Prompt "Port numarasi" -MinValue 1 -MaxValue 65535
#>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [double]$MinValue = [double]::MinValue,
        [double]$MaxValue = [double]::MaxValue,
        [string]$DefaultValue = '',
        [bool]$AllowDecimal = $false
    )

    while ($true) {
        $rangeHint = ''
        if ($MinValue -ne [double]::MinValue -and $MaxValue -ne [double]::MaxValue) {
            $rangeHint = " [$MinValue-$MaxValue]"
        } elseif ($MinValue -ne [double]::MinValue) {
            $rangeHint = " [min: $MinValue]"
        } elseif ($MaxValue -ne [double]::MaxValue) {
            $rangeHint = " [maks: $MaxValue]"
        }
        $defHint = if ($DefaultValue -ne '') { " (Varsayilan: $DefaultValue)" } else { '' }
        Write-Host "  $Prompt$rangeHint$defHint (0=Iptal) : " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host

        if ($null -eq $inp) { $inp = '' }
        $inp = $inp.Trim()

        if ($inp -eq '0') { return $null }   # iptal

        if ($inp -eq '' -and $DefaultValue -ne '') {
            $inp = $DefaultValue
        } elseif ($inp -eq '') {
            Write-Host '  [UYARI] Bir sayi giriniz.' -ForegroundColor Yellow
            continue
        }

        $parsed = 0.0
        $ok = if ($AllowDecimal) { [double]::TryParse($inp, [ref]$parsed) }
              else {
                  $pi = 0
                  $r = [int]::TryParse($inp, [ref]$pi)
                  $parsed = $pi
                  $r
              }

        if (-not $ok) {
            Write-Host '  [UYARI] Gecerli bir sayi giriniz.' -ForegroundColor Yellow
            continue
        }

        if ($parsed -lt $MinValue -or $parsed -gt $MaxValue) {
            Write-Host "  [UYARI] Deger $MinValue ile $MaxValue arasinda olmalidir." -ForegroundColor Yellow
            continue
        }

        if ($AllowDecimal) { return $parsed } else { return [int]$parsed }
    }
}

function Read-UserChoice {
<#
.SYNOPSIS
    Numaralandirilmis listeden kullanici secimi alir. 0 = geri/iptal.
.PARAMETER Title
    Liste basligini gosterir.
.PARAMETER Options
    Secenekler dizisi (string[]).
.PARAMETER Color
    Seceneklerin rengi (varsayilan: Cyan).
.RETURNS
    Secilen indeks (1 tabanli). $null = geri/iptal.
.EXAMPLE
    $sec = Read-UserChoice -Title "Platform secin" -Options @("Windows","Linux","macOS")
#>
    param(
        [string]$Title = 'Bir secenek secin',
        [Parameter(Mandatory)][string[]]$Options,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    Write-Host ''
    Write-Host "  $Title" -ForegroundColor $Color
    Write-Host ('  ' + ('-' * [Math]::Min($Title.Length + 2, 70))) -ForegroundColor DarkCyan

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $numTag = if (($i + 1) -lt 10) { "[ $($i+1)]" } else { "[$($i+1)]" }
        Write-Host "  $numTag  $($Options[$i])" -ForegroundColor $Color
    }
    Write-Host ''
    Write-Host '  [  0]  Geri / Iptal' -ForegroundColor Red
    Write-Host ''

    while ($true) {
        Write-Host "  Seciminiz [1-$($Options.Count) | 0=Geri]: " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host
        if ($null -eq $inp) { $inp = '' }
        $inp = $inp.Trim()

        if ($inp -eq '0' -or $inp -eq '00') { return $null }

        $idx = 0
        if ([int]::TryParse($inp, [ref]$idx) -and $idx -ge 1 -and $idx -le $Options.Count) {
            return $idx
        }
        Write-Host "  [UYARI] Lutfen 1 ile $($Options.Count) arasinda bir sayi giriniz." -ForegroundColor Yellow
    }
}

function Read-UserYesNo {
<#
.SYNOPSIS
    Kullanicidan E/H (Evet/Hayir) cevabi alir.
.PARAMETER Prompt
    Soru metni.
.PARAMETER DefaultYes
    $true ise varsayilan Evet, $false ise Hayir (Enter = varsayilan).
.RETURNS
    $true = Evet, $false = Hayir
.EXAMPLE
    if (Read-UserYesNo -Prompt "Devam edilsin mi?" -DefaultYes $true) { ... }
#>
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$DefaultYes = $true
    )

    $hint = if ($DefaultYes) { '[E/h]' } else { '[e/H]' }

    while ($true) {
        Write-Host "  $Prompt $hint : " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host
        if ($null -eq $inp) { $inp = '' }
        $inp = $inp.Trim().ToLower()

        if ($inp -eq '') { return $DefaultYes }
        if ($inp -in 'e', 'evet', 'y', 'yes', '1') { return $true }
        if ($inp -in 'h', 'hayir', 'n', 'no', '0') { return $false }
        Write-Host "  [UYARI] Lutfen 'E' (Evet) veya 'H' (Hayir) giriniz." -ForegroundColor Yellow
    }
}

# ==============================================================================
# BOLUM 3: GORUNUM / UI FONKSİYONLARI
# ==============================================================================

function Show-StepHeader {
<#
.SYNOPSIS
    Adim basligini gosterir. Ornek: "Adim 2/15 - WinGet Kimligi"
.PARAMETER CurrentStep
    Mevcut adim numarasi.
.PARAMETER TotalSteps
    Toplam adim sayisi.
.PARAMETER StepTitle
    Adim basliginin metni.
.EXAMPLE
    Show-StepHeader -CurrentStep 2 -TotalSteps 15 -StepTitle "WinGet Kimligi"
#>
    param(
        [Parameter(Mandatory)][int]$CurrentStep,
        [Parameter(Mandatory)][int]$TotalSteps,
        [Parameter(Mandatory)][string]$StepTitle
    )

    Write-Host ''
    $progressBar = ''
    $pct = [Math]::Round(($CurrentStep / $TotalSteps) * 20)
    $progressBar = '[' + ('#' * $pct) + ('-' * (20 - $pct)) + ']'
    $pctVal = [Math]::Round(($CurrentStep / $TotalSteps) * 100)

    Write-Host "  Adim $CurrentStep/$TotalSteps  $progressBar  %$pctVal" -ForegroundColor DarkCyan
    Write-Host "  >> $StepTitle" -ForegroundColor Cyan
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color DarkCyan -Char '-'
    } else {
        Write-Host ('  ' + ('-' * 76)) -ForegroundColor DarkCyan
    }
    Write-Host ''
}

function Show-FieldPrompt {
<#
.SYNOPSIS
    Alan adi ve mevcut/varsayilan degeri gosterir.
.PARAMETER FieldName
    Alan etiketi.
.PARAMETER CurrentValue
    Mevcut kayitli deger (bos ise "Girilmemis" gosterilir).
.PARAMETER IsRequired
    $true ise alan zorunlu olarak isaretle.
.EXAMPLE
    Show-FieldPrompt -FieldName "Uygulama Adi" -CurrentValue $app.Name
#>
    param(
        [Parameter(Mandatory)][string]$FieldName,
        [string]$CurrentValue = '',
        [bool]$IsRequired = $false
    )

    $reqMark = if ($IsRequired) { ' *' } else { '  ' }
    Write-Host "  $reqMark$FieldName" -ForegroundColor DarkCyan -NoNewline
    Write-Host ' : ' -ForegroundColor DarkCyan -NoNewline

    if ($CurrentValue -and $CurrentValue -ne '') {
        Write-Host $CurrentValue -ForegroundColor White
    } else {
        Write-Host '(girilmemis)' -ForegroundColor DarkCyan
    }
}

function Show-OperationSummary {
<#
.SYNOPSIS
    Girilen verilerin ozet tablosunu gosterir.
.PARAMETER Title
    Ozet basligini gosterir.
.PARAMETER Fields
    Hashtable: @{ "Alan Adi" = "Deger"; ... } veya [ordered]@{...}
.PARAMETER HighlightColor
    Deger metni rengi (varsayilan: White).
.EXAMPLE
    Show-OperationSummary -Title "Uygulama Ozeti" -Fields @{ "Ad" = "Firefox"; "Versiyon" = "120" }
#>
    param(
        [string]$Title = 'Islem Ozeti',
        [Parameter(Mandatory)]$Fields,
        [ConsoleColor]$HighlightColor = [ConsoleColor]::White
    )

    Write-Host ''
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color DarkCyan -Char '='
    } else {
        Write-Host ('  ' + ('=' * 76)) -ForegroundColor DarkCyan
    }
    Write-Host "  $Title" -ForegroundColor Magenta
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color DarkCyan -Char '-'
    } else {
        Write-Host ('  ' + ('-' * 76)) -ForegroundColor DarkCyan
    }

    $keys = if ($Fields -is [System.Collections.Specialized.OrderedDictionary] -or
                $Fields -is [System.Collections.Hashtable]) {
        $Fields.Keys
    } else {
        @()
    }

    $maxKeyLen = 0
    foreach ($k in $keys) { if ($k.Length -gt $maxKeyLen) { $maxKeyLen = $k.Length } }
    if ($maxKeyLen -lt 20) { $maxKeyLen = 20 }

    foreach ($k in $keys) {
        $label = $k.PadRight($maxKeyLen)
        $val = if ($Fields[$k] -ne $null -and $Fields[$k] -ne '') { $Fields[$k] } else { '(bos)' }
        Write-Host "  $label : " -ForegroundColor DarkCyan -NoNewline
        Write-Host "$val" -ForegroundColor $HighlightColor
    }

    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color DarkCyan -Char '='
    } else {
        Write-Host ('  ' + ('=' * 76)) -ForegroundColor DarkCyan
    }
    Write-Host ''
}

function Show-SuccessMessage {
<#
.SYNOPSIS
    Yesil banner ile basari mesaji gosterir.
.PARAMETER Message
    Basari mesajinin metni.
.PARAMETER AutoPause
    $true ise kullanici tusuna basmadan 2 saniye bekler ve devam eder.
.EXAMPLE
    Show-SuccessMessage -Message "Uygulama basariyla eklendi."
#>
    param(
        [Parameter(Mandatory)][string]$Message,
        [bool]$AutoPause = $false,
        [int]$PauseSeconds = 2
    )

    Write-Host ''
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color Green -Char '='
    } else {
        Write-Host ('  ' + ('=' * 76)) -ForegroundColor Green
    }
    Write-Host "  [BASARILI] $Message" -ForegroundColor Green
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color Green -Char '='
    } else {
        Write-Host ('  ' + ('=' * 76)) -ForegroundColor Green
    }
    Write-Host ''

    script:Write-ModuleLog "BASARILI: $Message" 'SUCCESS'

    if ($AutoPause) {
        Start-Sleep -Seconds $PauseSeconds
    } else {
        if (Get-Command 'Wait-UserKeyPress' -ErrorAction SilentlyContinue) {
            Wait-UserKeyPress
        } else {
            Write-Host '  Devam etmek icin Enter tusuna basin...' -ForegroundColor DarkCyan
            $null = Read-Host
        }
    }
}

function Show-ErrorMessage {
<#
.SYNOPSIS
    Kirmizi banner ile hata mesaji gosterir ve loglar.
.PARAMETER Message
    Hata mesajinin metni.
.PARAMETER Exception
    (Opsiyonel) Yakalanan istisna nesnesi - detaylari loglanir.
.PARAMETER AutoPause
    $true ise 3 saniye bekler (varsayilan $false = kullanici Enter basar).
.EXAMPLE
    Show-ErrorMessage -Message "Dosya okunamadi." -Exception $_
#>
    param(
        [Parameter(Mandatory)][string]$Message,
        [System.Exception]$Exception = $null,
        [bool]$AutoPause = $false,
        [int]$PauseSeconds = 3
    )

    Write-Host ''
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color Red -Char '!'
    } else {
        Write-Host ('  ' + ('!' * 76)) -ForegroundColor Red
    }
    Write-Host "  [HATA] $Message" -ForegroundColor Red
    if ($Exception) {
        Write-Host "  Detay: $($Exception.Message)" -ForegroundColor Red
    }
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color Red -Char '!'
    } else {
        Write-Host ('  ' + ('!' * 76)) -ForegroundColor Red
    }
    Write-Host ''

    $logMsg = "HATA: $Message"
    if ($Exception) { $logMsg += " | Detay: $($Exception.Message)" }
    script:Write-ModuleLog $logMsg 'ERROR'

    if ($AutoPause) {
        Start-Sleep -Seconds $PauseSeconds
    } else {
        if (Get-Command 'Wait-UserKeyPress' -ErrorAction SilentlyContinue) {
            Wait-UserKeyPress
        } else {
            Write-Host '  Devam etmek icin Enter tusuna basin...' -ForegroundColor DarkCyan
            $null = Read-Host
        }
    }
}

function Show-WarningMessage {
<#
.SYNOPSIS
    Sari banner ile uyari mesaji gosterir.
.PARAMETER Message
    Uyari mesajinin metni.
.PARAMETER AutoPause
    $true ise 2 saniye bekler (varsayilan $false = kullanici Enter basar).
.EXAMPLE
    Show-WarningMessage -Message "Bu islem geri alinamaz!"
#>
    param(
        [Parameter(Mandatory)][string]$Message,
        [bool]$AutoPause = $false,
        [int]$PauseSeconds = 2
    )

    Write-Host ''
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color Yellow -Char '-'
    } else {
        Write-Host ('  ' + ('-' * 76)) -ForegroundColor Yellow
    }
    Write-Host "  [UYARI] $Message" -ForegroundColor Yellow
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color Yellow -Char '-'
    } else {
        Write-Host ('  ' + ('-' * 76)) -ForegroundColor Yellow
    }
    Write-Host ''

    script:Write-ModuleLog "UYARI: $Message" 'WARN'

    if ($AutoPause) {
        Start-Sleep -Seconds $PauseSeconds
    } else {
        if (Get-Command 'Wait-UserKeyPress' -ErrorAction SilentlyContinue) {
            Wait-UserKeyPress
        } else {
            Write-Host '  Devam etmek icin Enter tusuna basin...' -ForegroundColor DarkCyan
            $null = Read-Host
        }
    }
}

# ==============================================================================
# BOLUM 4: JSON DOSYA YONETIMI
# ==============================================================================

function Test-JsonValid {
<#
.SYNOPSIS
    Bir string veya dosya icerigi icin JSON gecerliligini test eder.
.PARAMETER JsonString
    Test edilecek JSON metni.
.PARAMETER FilePath
    JSON dosyasinin tam yolu (JsonString ile birlikte kullanilmaz).
.RETURNS
    $true = gecerli JSON, $false = gecersiz
.EXAMPLE
    if (Test-JsonValid -FilePath 'data\apps.json') { ... }
#>
    param(
        [string]$JsonString = '',
        [string]$FilePath = ''
    )

    try {
        if ($FilePath -ne '' -and (Test-Path -LiteralPath $FilePath)) {
            $JsonString = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
        }
        if ($JsonString -eq '') { return $false }
        $null = ConvertFrom-Json $JsonString -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Read-JsonFile {
<#
.SYNOPSIS
    JSON dosyasini okur. Bozuk dosya ve eksik dosya korumasiyla.
.PARAMETER FilePath
    Okunacak JSON dosyasinin tam yolu.
.PARAMETER DefaultValue
    Dosya yoksa veya bozuksa dondurulecek varsayilan nesne.
.RETURNS
    PSCustomObject veya $DefaultValue
.EXAMPLE
    $data = Read-JsonFile -FilePath 'data\apps.json' -DefaultValue @{}
#>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        $DefaultValue = $null
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        script:Write-ModuleLog "Read-JsonFile: Dosya bulunamadi - $FilePath" 'WARN'
        return $DefaultValue
    }

    try {
        $raw = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)

        if ([string]::IsNullOrWhiteSpace($raw)) {
            script:Write-ModuleLog "Read-JsonFile: Dosya bos - $FilePath" 'WARN'
            return $DefaultValue
        }

        $parsed = ConvertFrom-Json $raw -ErrorAction Stop
        script:Write-ModuleLog "Read-JsonFile: Basariyla okundu - $FilePath" 'INFO'
        return $parsed
    } catch {
        script:Write-ModuleLog "Read-JsonFile: JSON ayristirma hatasi - $FilePath | $($_.Exception.Message)" 'ERROR'

        # Bozuk dosya varsa yedekle
        try {
            $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backupPath = "$FilePath.bozuk_$ts"
            Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force -ErrorAction SilentlyContinue
            script:Write-ModuleLog "Read-JsonFile: Bozuk dosya yedeklendi -> $backupPath" 'WARN'
        } catch {}

        return $DefaultValue
    }
}

function Write-JsonFile {
<#
.SYNOPSIS
    Veriyi JSON olarak atomik sekilde yazar (once temp, dogrula, sonra tasi).
    Mevcut dosyanin otomatik yedegiini alir.
.PARAMETER FilePath
    Yazilacak JSON dosyasinin tam yolu.
.PARAMETER Data
    JSON'a donusturulecek nesne.
.PARAMETER CreateBackup
    $true ise yazmadan once yedek alir (varsayilan: $true).
.RETURNS
    $true = basarili, $false = basarisiz
.EXAMPLE
    Write-JsonFile -FilePath 'data\apps.json' -Data $appList
#>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)]$Data,
        [bool]$CreateBackup = $true
    )

    try {
        # Hedef klasoru olustur
        $dir = Split-Path -Parent $FilePath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop
        }

        # JSON donusum
        $jsonContent = ConvertTo-Json -InputObject $Data -Depth 10 -ErrorAction Stop

        # Gecerlilik testi
        if (-not (Test-JsonValid -JsonString $jsonContent)) {
            script:Write-ModuleLog "Write-JsonFile: Uretilen JSON gecersiz - $FilePath" 'ERROR'
            return $false
        }

        # Mevcut dosyanin yedeğini al
        if ($CreateBackup -and (Test-Path -LiteralPath $FilePath)) {
            $null = Backup-DataFile -FilePath $FilePath -Silent $true
        }

        # Atomik yazma: once temp dosyaya yaz
        $tempPath = "$FilePath.tmp_$(Get-Date -Format 'HHmmssff')"
        [System.IO.File]::WriteAllText($tempPath, $jsonContent, [System.Text.Encoding]::UTF8)

        # Temp dosyanin okunabilirligini dogrula
        if (-not (Test-JsonValid -FilePath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            script:Write-ModuleLog "Write-JsonFile: Temp dosya dogrulanamadi - $FilePath" 'ERROR'
            return $false
        }

        # Atomik tasi (Move ile asil dosyanin ustune)
        if (Test-Path -LiteralPath $FilePath) {
            Remove-Item -LiteralPath $FilePath -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $tempPath -Destination $FilePath -Force -ErrorAction Stop

        script:Write-ModuleLog "Write-JsonFile: Basariyla yazildi - $FilePath" 'SUCCESS'
        return $true
    } catch {
        # Temp dosya kalmissa temizle
        try {
            $tempPattern = "$FilePath.tmp_*"
            Get-ChildItem -Path (Split-Path -Parent $FilePath) -Filter "$(Split-Path -Leaf $FilePath).tmp_*" -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {}

        script:Write-ModuleLog "Write-JsonFile: Yazma hatasi - $FilePath | $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Backup-DataFile {
<#
.SYNOPSIS
    Belirtilen dosyanin zaman damgali yedeğini data/backups/ klasorune olusturur.
.PARAMETER FilePath
    Yedeklenecek dosyanin tam yolu.
.PARAMETER Silent
    $true ise konsol ciktisi vermez.
.RETURNS
    Yedek dosyanin tam yolu ($null = basarisiz)
.EXAMPLE
    $backupPath = Backup-DataFile -FilePath 'data\apps.json'
#>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [bool]$Silent = $false
    )

    try {
        if (-not (Test-Path -LiteralPath $FilePath)) {
            if (-not $Silent) { Write-Host "  [UYARI] Yedeklenecek dosya bulunamadi: $FilePath" -ForegroundColor Yellow }
            script:Write-ModuleLog "Backup-DataFile: Dosya yok - $FilePath" 'WARN'
            return $null
        }

        $backupsDir = script:Get-BackupsDirectory
        $fileName   = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        $ext        = [System.IO.Path]::GetExtension($FilePath)
        $ts         = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupName = "${fileName}_${ts}${ext}"
        $backupPath = Join-Path $backupsDir $backupName

        Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force -ErrorAction Stop
        script:Write-ModuleLog "Backup-DataFile: Yedek olusturuldu -> $backupPath" 'SUCCESS'

        if (-not $Silent) {
            Write-Host "  [YEDEK] $backupName olusturuldu." -ForegroundColor Green
        }

        # Eski yedekleri temizle
        Remove-OldBackups -FileName $fileName -Extension $ext -Silent $Silent

        return $backupPath
    } catch {
        script:Write-ModuleLog "Backup-DataFile: Hata - $FilePath | $($_.Exception.Message)" 'ERROR'
        if (-not $Silent) { Write-Host "  [HATA] Yedek alinamadi: $($_.Exception.Message)" -ForegroundColor Red }
        return $null
    }
}

function Restore-DataFile {
<#
.SYNOPSIS
    Yedek listesini gosterir, kullanici secim yapar ve geri yukler.
.PARAMETER TargetFilePath
    Geri yuklenecek hedef dosyanin tam yolu.
.RETURNS
    $true = basarili geri yukleme, $false = iptal veya hata
.EXAMPLE
    Restore-DataFile -TargetFilePath 'data\apps.json'
#>
    param(
        [Parameter(Mandatory)][string]$TargetFilePath
    )

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($TargetFilePath)
    $ext      = [System.IO.Path]::GetExtension($TargetFilePath)
    $backups  = @(Get-BackupList -FileName $fileName -Extension $ext)

    if (-not $backups -or $backups.Count -eq 0) {
        Write-Host "  [BILGI] '$fileName' dosyasina ait yedek bulunamadi." -ForegroundColor Cyan
        script:Write-ModuleLog "Restore-DataFile: Yedek yok - $fileName" 'WARN'
        return $false
    }

    Write-Host ''
    Write-Host "  Mevcut Yedekler: $fileName$ext" -ForegroundColor Cyan
    if (Get-Command 'Draw-HorizontalLine' -ErrorAction SilentlyContinue) {
        Draw-HorizontalLine -Width 78 -Color DarkCyan -Char '-'
    }

    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b = $backups[$i]
        $sizeFmt = if ($b.Length -ge 1MB) { '{0:N2} MB' -f ($b.Length / 1MB) }
                   elseif ($b.Length -ge 1KB) { '{0:N2} KB' -f ($b.Length / 1KB) }
                   else { "$($b.Length) Byte" }
        $numTag = if (($i + 1) -lt 10) { "[ $($i+1)]" } else { "[$($i+1)]" }
        Write-Host "  $numTag  $($b.Name)  ($sizeFmt)  $('{0:yyyy-MM-dd HH:mm:ss}' -f $b.LastWriteTime)" -ForegroundColor White
    }

    Write-Host ''
    Write-Host '  [  0]  Iptal' -ForegroundColor Red
    Write-Host ''

    while ($true) {
        Write-Host "  Geri yuklenecek yedegi secin [1-$($backups.Count) | 0=Iptal]: " -ForegroundColor Yellow -NoNewline
        $inp = Read-Host
        if ($null -eq $inp) { $inp = '' }
        $inp = $inp.Trim()

        if ($inp -eq '0') { return $false }

        $idx = 0
        if ([int]::TryParse($inp, [ref]$idx) -and $idx -ge 1 -and $idx -le $backups.Count) {
            $selectedBackup = $backups[$idx - 1]
            break
        }
        Write-Host "  [UYARI] Gecersiz secim." -ForegroundColor Yellow
    }

    # Hedef dosyanin mevcut halini yedekle
    if (Test-Path -LiteralPath $TargetFilePath) {
        $null = Backup-DataFile -FilePath $TargetFilePath -Silent $true
    }

    try {
        $dir = Split-Path -Parent $TargetFilePath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -Path $dir -ItemType Directory -Force
        }
        Copy-Item -LiteralPath $selectedBackup.FullName -Destination $TargetFilePath -Force -ErrorAction Stop
        script:Write-ModuleLog "Restore-DataFile: Geri yuklendi - $($selectedBackup.Name) -> $TargetFilePath" 'SUCCESS'
        Write-Host "  [BASARILI] $($selectedBackup.Name) basariyla geri yuklendi." -ForegroundColor Green
        return $true
    } catch {
        script:Write-ModuleLog "Restore-DataFile: Geri yukleme hatasi - $($_.Exception.Message)" 'ERROR'
        Write-Host "  [HATA] Geri yukleme basarisiz: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-BackupList {
<#
.SYNOPSIS
    Belirli bir dosyaya ait yedekleri listeler (en yeni -> en eski).
.PARAMETER FileName
    Uzantisiz dosya adi.
.PARAMETER Extension
    Dosya uzantisi (ornek: '.json')
.RETURNS
    FileInfo[] dizisi (bos olabilir)
.EXAMPLE
    $backups = Get-BackupList -FileName 'apps' -Extension '.json'
#>
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$Extension = '.json'
    )

    try {
        $backupsDir = script:Get-BackupsDirectory
        $pattern    = "${FileName}_*${Extension}"
        $results    = @(Get-ChildItem -Path $backupsDir -Filter $pattern -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending)
        return $results
    } catch {
        script:Write-ModuleLog "Get-BackupList: Hata - $($_.Exception.Message)" 'ERROR'
        return @()
    }
}

function Remove-OldBackups {
<#
.SYNOPSIS
    Belirtilen dosyaya ait yedek sayisi 10'dan fazlaysa eskilerini temizler.
.PARAMETER FileName
    Uzantisiz dosya adi.
.PARAMETER Extension
    Dosya uzantisi (ornek: '.json')
.PARAMETER MaxBackups
    Saklanacak maksimum yedek sayisi (varsayilan: 10)
.PARAMETER Silent
    $true ise konsol ciktisi vermez.
.EXAMPLE
    Remove-OldBackups -FileName 'apps' -Extension '.json'
#>
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string]$Extension = '.json',
        [int]$MaxBackups = 10,
        [bool]$Silent = $false
    )

    try {
        $backups = @(Get-BackupList -FileName $FileName -Extension $Extension)

        if ($backups.Count -le $MaxBackups) { return }

        $toDelete = @($backups | Select-Object -Skip $MaxBackups)
        $deletedCount = 0
        foreach ($f in $toDelete) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                $deletedCount++
            } catch {}
        }

        if ($deletedCount -gt 0) {
            script:Write-ModuleLog "Remove-OldBackups: $deletedCount eski yedek silindi ($FileName)" 'INFO'
            if (-not $Silent) {
                Write-Host "  [TEMIZLIK] $deletedCount eski yedek dosyasi silindi." -ForegroundColor DarkCyan
            }
        }
    } catch {
        script:Write-ModuleLog "Remove-OldBackups: Hata - $($_.Exception.Message)" 'ERROR'
    }
}

# ==============================================================================
# BOLUM 5: MODULE EXPORT
# ==============================================================================

Export-ModuleMember -Function @(
    # Veri giris fonksiyonlari
    'Read-UserText',
    'Read-UserNumber',
    'Read-UserChoice',
    'Read-UserYesNo',
    # UI / gorunum fonksiyonlari
    'Show-StepHeader',
    'Show-FieldPrompt',
    'Show-OperationSummary',
    'Show-SuccessMessage',
    'Show-ErrorMessage',
    'Show-WarningMessage',
    # JSON dosya yonetimi
    'Read-JsonFile',
    'Write-JsonFile',
    'Backup-DataFile',
    'Restore-DataFile',
    'Test-JsonValid',
    'Get-BackupList',
    'Remove-OldBackups'
)
