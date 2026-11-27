#Requires -Version 5.1
<#
.SYNOPSIS
    AAU Kurulum Asistani - Katalog Yonetim Modulu
.DESCRIPTION
    Program ekleme, duzenleme, silme ve kategori yonetimi icin tam etkilesimli konsol menuleri.
    admin_core.psm1 modulune bagimlidir.
.NOTES
    Yazar    : AAU Kurulum Asistani
    Surum    : 1.0.0
    Uyumluluk: PowerShell 5.1+
#>

#region --- YARDIMCI FONKSIYONLAR ---

$adminCorePath = Join-Path $PSScriptRoot "admin_core.psm1"
if (Test-Path $adminCorePath) {
    Import-Module $adminCorePath -Global -ErrorAction SilentlyContinue
}

function Get-AppsJsonPath {
    if ($script:DataDir) {
        return Join-Path $script:DataDir "apps\apps.json"
    }
    if ($global:DataDir) {
        return Join-Path $global:DataDir "apps\apps.json"
    }
    $root = if ($global:ProjectRoot) { $global:ProjectRoot }
            elseif ($script:ProjectRoot) { $script:ProjectRoot }
            else { (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) }
    return Join-Path $root "data\apps\apps.json"
}

function Get-CatalogData {
    $path = Get-AppsJsonPath
    if (-not (Test-Path $path)) {
        return [PSCustomObject]@{
            version      = "1.0.0"
            last_updated = (Get-Date -Format "yyyy-MM-dd")
            description  = "AAU Kurulum Asistani - Uygulama Katalogu"
            categories   = @()
            applications = @()
        }
    }
    $data = Read-JsonFile -FilePath $path
    if (-not $data) {
        return $null
    }
    return $data
}

function Save-CatalogData {
    param([Parameter(Mandatory)][PSCustomObject]$Data)
    $path = Get-AppsJsonPath
    $Data.last_updated = Get-Date -Format "yyyy-MM-dd"
    return Write-JsonFile -FilePath $path -Data $Data
}

function Show-CatalogHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Magenta
    Write-Host ("  KATALOG YONETIMI :: $Title").ToUpper() -ForegroundColor Magenta
    Write-Host ("=" * 70) -ForegroundColor Magenta
    Write-Host ""
}

function Show-ApplicationList {
    param(
        [Parameter(Mandatory)][array]$Applications,
        [string]$Title = "Uygulama Listesi"
    )
    Write-Host ""
    Write-Host ("  " + ("=" * 76)) -ForegroundColor DarkCyan
    Write-Host "  $Title (Kategori / Katalog Bazli Liste)" -ForegroundColor Magenta
    Write-Host ("  " + ("=" * 76)) -ForegroundColor DarkCyan

    # Kategorilere gore grupla
    $grouped = $Applications | Group-Object -Property Category
    foreach ($grp in $grouped) {
        $catHeader = switch ("$($grp.Name)".ToLower()) {
            "browsers"      { "🌐 TARAYICILAR (browsers)" }
            "utilities"     { "🔧 TEMEL SISTEM ARACLARI (utilities)" }
            "media"         { "🎬 MEDYA, GORSEL VE SES (media)" }
            "office"        { "📄 OFIS VE DOKUMAN (office)" }
            "communication" { "💬 ILETISIM (communication)" }
            "gaming"        { "🎮 OYUN PLATFORMLARI (gaming)" }
            "developer"     { "💻 GELISTIRICI ARACLARI (developer)" }
            "runtime"       { "⚙️  SISTEM BILESENLERI (runtime)" }
            default         { "📁 $($grp.Name.ToUpper())" }
        }

        Write-Host ""
        Write-Host "  $catHeader" -ForegroundColor Cyan
        Write-Host ("  " + ("-" * 76)) -ForegroundColor DarkCyan
        Write-Host ("    {0,-5} {1,-30} {2,-24} {3}" -f "No", "Program Adi", "WinGet ID", "Durum") -ForegroundColor DarkCyan

        foreach ($app in $grp.Group) {
            $origIdx = [array]::IndexOf($Applications, $app) + 1
            $name = if ($app.Name.Length -gt 28) { $app.Name.Substring(0,25) + "..." } else { $app.Name }
            $id   = if ($app.Id.Length -gt 22)   { $app.Id.Substring(0,19) + "..."   } else { $app.Id }
            $en   = if ($app.Enabled) { "[Aktif]" } else { "[Pasif]" }
            $enColor = if ($app.Enabled) { [ConsoleColor]::Green } else { [ConsoleColor]::DarkGray }

            Write-Host ("    [{0,2}] " -f $origIdx) -ForegroundColor Yellow -NoNewline
            Write-Host ("{0,-30} " -f $name) -ForegroundColor White -NoNewline
            Write-Host ("{0,-24} " -f $id) -ForegroundColor Cyan -NoNewline
            Write-Host $en -ForegroundColor $enColor
        }
    }
    Write-Host ""
    Write-Host ("  " + ("=" * 76)) -ForegroundColor DarkCyan
    Write-Host "  Toplam: $($Applications.Count) program listelendi." -ForegroundColor White
    Write-Host ""
}

function Show-ApplicationDetail {
    param([Parameter(Mandatory)][PSCustomObject]$App)
    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor DarkCyan
    Write-Host "  PROGRAM DETAYLARI" -ForegroundColor Cyan
    Write-Host ("-" * 60) -ForegroundColor DarkCyan
    $fields = @(
        @{ L = " 1. Program Adi";       V = $App.Name }
        @{ L = " 2. WinGet ID";         V = $App.Id }
        @{ L = " 3. Yayinci";           V = $App.Publisher }
        @{ L = " 4. Kategori";          V = $App.Category }
        @{ L = " 5. Aciklama";          V = $App.Description }
        @{ L = " 6. Web Sitesi";        V = $App.Website }
        @{ L = " 7. Paket Kaynagi";     V = $App.Source }
        @{ L = " 8. Mimari";            V = $App.Architecture }
        @{ L = " 9. Kapsam";            V = $App.Scope }
        @{ L = "10. Kurulum Turu";      V = $App.InstallType }
        @{ L = "11. Sessiz Kurulum";    V = if ($App.SilentInstall) { "Evet" } else { "Hayir" } }
        @{ L = "12. Ozel Parametreler"; V = if ($App.CustomArguments) { $App.CustomArguments } else { "(bos)" } }
        @{ L = "13. Surum";             V = $App.Version }
        @{ L = "14. Etkin";             V = if ($App.Enabled) { "Evet" } else { "Hayir" } }
        @{ L = "15. Kurulum Sirasi";    V = $App.InstallOrder }
    )
    foreach ($f in $fields) {
        Write-Host ("  {0,-25}: {1}" -f $f.L, $f.V) -ForegroundColor White
    }
    Write-Host ("-" * 60) -ForegroundColor DarkCyan
    Write-Host ""
}

function Select-ApplicationFromList {
    param(
        [Parameter(Mandatory)][array]$Applications,
        [string]$Prompt = "Uygulama numarasini girin"
    )
    Show-ApplicationList -Applications $Applications
    while ($true) {
        Write-Host "  $Prompt [0=Iptal]: " -ForegroundColor Yellow -NoNewline
        $input = Read-Host
        if ($input -eq "0" -or $input -eq "") { return $null }
        $num = 0
        if ([int]::TryParse($input, [ref]$num) -and $num -ge 1 -and $num -le $Applications.Count) {
            return $Applications[$num - 1]
        }
        Write-Host "  [!] Gecersiz numara. 1 ile $($Applications.Count) arasinda bir deger girin." -ForegroundColor Red
    }
}

function Get-NextInstallOrder {
    param([array]$Applications)
    if (-not $Applications -or $Applications.Count -eq 0) { return 1 }
    $max = ($Applications | Measure-Object -Property InstallOrder -Maximum).Maximum
    return $max + 1
}

#endregion

#region --- PROGRAM EKLEME: Invoke-AddApplication ---

function Invoke-AddApplication {
    <#
    .SYNOPSIS
        15 adimli wizard ile yeni program ekler.
    #>
    Show-CatalogHeader -Title "Yeni Program Ekle"

    $data = Get-CatalogData
    if (-not $data) {
        Write-Host "  [HATA] Katalog verisi yuklenemedi." -ForegroundColor Red
        return
    }

    # Wizard state
    $wizard = @{
        Name            = ""
        Id              = ""
        Publisher       = ""
        Category        = ""
        Description     = ""
        Website         = ""
        Source          = "winget"
        Architecture    = "x64"
        Scope           = "machine"
        InstallType     = "standard"
        SilentInstall   = $true
        CustomArguments = ""
        Version         = "latest"
        Enabled         = $true
        InstallOrder    = (Get-NextInstallOrder -Applications $data.applications)
    }

    $step = 1
    $totalSteps = 15

    while ($step -le $totalSteps) {
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Magenta
        Write-Host ("  Adim $step/$totalSteps") -ForegroundColor Magenta

        switch ($step) {

            # --- ADIM 1: Program Adi ---
            1 {
                Write-Host "  Program Adi (zorunlu)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                if ($wizard.Name) {
                    Write-Host "  Mevcut: $($wizard.Name)" -ForegroundColor Cyan
                }
                Write-Host "  [0]=Iptal | [Enter]=Atla (mevcut degeri koru)" -ForegroundColor DarkCyan
                Write-Host ""
                Write-Host "  Program Adi: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "" -and $wizard.Name -ne "") { $step++; continue }
                if ($val -eq "") {
                    Write-Host "  [!] Program adi bos olamaz." -ForegroundColor Red
                    continue
                }
                $wizard.Name = $val
                $step++
            }

            # --- ADIM 2: WinGet ID ---
            2 {
                Write-Host "  WinGet Paket Kimligi (zorunlu, ornek: Google.Chrome)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                if ($wizard.Id) {
                    Write-Host "  Mevcut: $($wizard.Id)" -ForegroundColor Cyan
                }
                Write-Host "  [B]=Onceki Adim | [0]=Iptal | [Enter]=Atla (mevcut degeri koru)" -ForegroundColor DarkCyan
                Write-Host ""
                Write-Host "  WinGet ID: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "" -and $wizard.Id -ne "") { $step++; continue }
                if ($val -eq "") {
                    Write-Host "  [!] WinGet ID bos olamaz." -ForegroundColor Red
                    continue
                }
                # Tekrar kontrolu
                $existing = $data.applications | Where-Object { $_.Id -eq $val }
                if ($existing) {
                    Write-Host "  [!] Bu WinGet ID zaten katalogda mevcut: $($existing.Name)" -ForegroundColor Red
                    Write-Host "  Farkli bir ID girin veya [B] ile onceki adima donun." -ForegroundColor Yellow
                    continue
                }
                $wizard.Id = $val
                $step++
            }

            # --- ADIM 3: Yayinci ---
            3 {
                Write-Host "  Yayinci (zorunlu)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                if ($wizard.Publisher) {
                    Write-Host "  Mevcut: $($wizard.Publisher)" -ForegroundColor Cyan
                }
                Write-Host "  [B]=Onceki Adim | [0]=Iptal | [Enter]=Atla (mevcut degeri koru)" -ForegroundColor DarkCyan
                Write-Host ""
                Write-Host "  Yayinci: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "" -and $wizard.Publisher -ne "") { $step++; continue }
                if ($val -eq "") {
                    Write-Host "  [!] Yayinci bos olamaz." -ForegroundColor Red
                    continue
                }
                $wizard.Publisher = $val
                $step++
            }

            # --- ADIM 4: Kategori ---
            4 {
                Write-Host "  Kategori Secimi" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal | [K]=Yeni Kategori Olustur" -ForegroundColor DarkCyan
                Write-Host ""

                $cats = @($data.categories)
                $i = 1
                foreach ($cat in $cats) {
                    $marker = if ($cat.id -eq $wizard.Category) { " <-- secili" } else { "" }
                    Write-Host ("  [{0}] {1} {2}{3}" -f $i, $cat.icon, $cat.name, $marker) -ForegroundColor White
                    $i++
                }
                Write-Host "  [K] Yeni kategori olustur" -ForegroundColor Green
                Write-Host ""
                Write-Host "  Secim: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host

                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "K" -or $val -eq "k") {
                    # Yeni kategori ekle
                    Write-Host ""
                    Write-Host "  Yeni Kategori Olustur:" -ForegroundColor Green
                    Write-Host "  Kategori ID (kucuk harf, bosluksuz): " -ForegroundColor Yellow -NoNewline
                    $newId = Read-Host
                    if ($newId -eq "" -or $newId -eq "0") { continue }
                    $newId = $newId.ToLower() -replace '\s', '_'

                    Write-Host "  Kategori Adi: " -ForegroundColor Yellow -NoNewline
                    $newName = Read-Host
                    if ($newName -eq "") { continue }

                    Write-Host "  Ikon (emoji, bos birakilabilir): " -ForegroundColor Yellow -NoNewline
                    $newIcon = Read-Host
                    if ($newIcon -eq "") { $newIcon = "📦" }

                    $newCat = [PSCustomObject]@{ id = $newId; name = $newName; icon = $newIcon }
                    $catList = [System.Collections.ArrayList]@($data.categories)
                    $catList.Add($newCat) | Out-Null
                    $data.categories = $catList.ToArray()
                    $wizard.Category = $newId
                    Write-Host "  [OK] Yeni kategori olusturuldu: $newIcon $newName" -ForegroundColor Green
                    $step++
                    continue
                }

                $num = 0
                if ([int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le $cats.Count) {
                    $wizard.Category = $cats[$num - 1].id
                    $step++
                } else {
                    Write-Host "  [!] Gecersiz secim." -ForegroundColor Red
                }
            }

            # --- ADIM 5: Aciklama ---
            5 {
                Write-Host "  Aciklama (opsiyonel)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                if ($wizard.Description) {
                    Write-Host "  Mevcut: $($wizard.Description)" -ForegroundColor Cyan
                }
                Write-Host "  [B]=Onceki Adim | [0]=Iptal | [Enter]=Bos birak/Koru" -ForegroundColor DarkCyan
                Write-Host ""
                Write-Host "  Aciklama: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -ne "") { $wizard.Description = $val }
                $step++
            }

            # --- ADIM 6: Web Sitesi ---
            6 {
                Write-Host "  Resmi Web Sitesi (opsiyonel)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                if ($wizard.Website) {
                    Write-Host "  Mevcut: $($wizard.Website)" -ForegroundColor Cyan
                }
                Write-Host "  [B]=Onceki Adim | [0]=Iptal | [Enter]=Bos birak/Koru" -ForegroundColor DarkCyan
                Write-Host ""
                Write-Host "  Web Sitesi: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -ne "") { $wizard.Website = $val }
                $step++
            }

            # --- ADIM 7: Paket Kaynagi ---
            7 {
                Write-Host "  Paket Kaynagi" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal" -ForegroundColor DarkCyan
                Write-Host ""
                $sources = @("winget", "msstore", "other")
                $i = 1
                foreach ($s in $sources) {
                    $marker = if ($s -eq $wizard.Source) { " <-- mevcut" } else { "" }
                    Write-Host "  [$i] $s$marker" -ForegroundColor White
                    $i++
                }
                Write-Host ""
                Write-Host "  Secim [1-3]: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "" ) { $step++; continue }
                $num = 0
                if ([int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le 3) {
                    $wizard.Source = $sources[$num - 1]
                    $step++
                } else {
                    Write-Host "  [!] Gecersiz secim. 1, 2 veya 3 girin." -ForegroundColor Red
                }
            }

            # --- ADIM 8: Mimari ---
            8 {
                Write-Host "  Mimari" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal" -ForegroundColor DarkCyan
                Write-Host ""
                $archs = @("x64", "x86", "arm64", "any")
                $i = 1
                foreach ($a in $archs) {
                    $marker = if ($a -eq $wizard.Architecture) { " <-- mevcut" } else { "" }
                    Write-Host "  [$i] $a$marker" -ForegroundColor White
                    $i++
                }
                Write-Host ""
                Write-Host "  Secim [1-4]: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "") { $step++; continue }
                $num = 0
                if ([int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le 4) {
                    $wizard.Architecture = $archs[$num - 1]
                    $step++
                } else {
                    Write-Host "  [!] Gecersiz secim. 1 ile 4 arasinda girin." -ForegroundColor Red
                }
            }

            # --- ADIM 9: Kapsam ---
            9 {
                Write-Host "  Kurulum Kapsami" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal" -ForegroundColor DarkCyan
                Write-Host ""
                $scopes = @("machine", "user")
                $i = 1
                foreach ($s in $scopes) {
                    $marker = if ($s -eq $wizard.Scope) { " <-- mevcut" } else { "" }
                    Write-Host "  [$i] $s$marker" -ForegroundColor White
                    $i++
                }
                Write-Host ""
                Write-Host "  Secim [1-2]: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "") { $step++; continue }
                $num = 0
                if ([int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le 2) {
                    $wizard.Scope = $scopes[$num - 1]
                    $step++
                } else {
                    Write-Host "  [!] Gecersiz secim. 1 veya 2 girin." -ForegroundColor Red
                }
            }

            # --- ADIM 10: Kurulum Turu ---
            10 {
                Write-Host "  Kurulum Turu" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal" -ForegroundColor DarkCyan
                Write-Host ""
                $types = @("standard", "portable", "direct_url", "other")
                $i = 1
                foreach ($t in $types) {
                    $marker = if ($t -eq $wizard.InstallType) { " <-- mevcut" } else { "" }
                    Write-Host "  [$i] $t$marker" -ForegroundColor White
                    $i++
                }
                Write-Host ""
                Write-Host "  Secim [1-4]: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "") { $step++; continue }
                $num = 0
                if ([int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le 4) {
                    $wizard.InstallType = $types[$num - 1]
                    if ($wizard.InstallType -eq "direct_url") {
                        Write-Host "  Indirme URL'si (https://...): " -ForegroundColor Yellow -NoNewline
                        $dlUrl = Read-Host
                        if ($dlUrl -and $dlUrl.Trim() -match '^https?://') {
                            $wizard['DownloadUrl'] = $dlUrl.Trim()
                            $wizard['Source'] = 'direct_url'
                        }
                    }
                    $step++
                } else {
                    Write-Host "  [!] Gecersiz secim. 1, 2, 3 veya 4 girin." -ForegroundColor Red
                }
            }

            # --- ADIM 11: Sessiz Kurulum ---
            11 {
                Write-Host "  Sessiz Kurulum" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal" -ForegroundColor DarkCyan
                $curVal = if ($wizard.SilentInstall) { "Evet [E]" } else { "Hayir [H]" }
                Write-Host "  Mevcut: $curVal" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  Sessiz kurulum? [E/H]: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "") { $step++; continue }
                if ($val -eq "E" -or $val -eq "e") { $wizard.SilentInstall = $true; $step++ }
                elseif ($val -eq "H" -or $val -eq "h") { $wizard.SilentInstall = $false; $step++ }
                else { Write-Host "  [!] E veya H girin." -ForegroundColor Red }
            }

            # --- ADIM 12: Ozel Parametreler ---
            12 {
                Write-Host "  Ozel Kurulum Parametreleri (opsiyonel)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal | [Enter]=Bos birak/Koru" -ForegroundColor DarkCyan
                if ($wizard.CustomArguments) {
                    Write-Host "  Mevcut: $($wizard.CustomArguments)" -ForegroundColor Cyan
                }
                Write-Host ""
                Write-Host "  Parametreler: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -ne "") { $wizard.CustomArguments = $val }
                $step++
            }

            # --- ADIM 13: Surum ---
            13 {
                Write-Host "  Surum (varsayilan: latest)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal | [Enter]=latest koru" -ForegroundColor DarkCyan
                Write-Host "  Mevcut: $($wizard.Version)" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  Surum: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -ne "") { $wizard.Version = $val }
                $step++
            }

            # --- ADIM 14: Etkin Mi ---
            14 {
                Write-Host "  Program Etkin Mi? (varsayilan: Evet)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal" -ForegroundColor DarkCyan
                $curVal = if ($wizard.Enabled) { "Evet [E]" } else { "Hayir [H]" }
                Write-Host "  Mevcut: $curVal" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  Etkin mi? [E/H]: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -eq "") { $step++; continue }
                if ($val -eq "E" -or $val -eq "e") { $wizard.Enabled = $true; $step++ }
                elseif ($val -eq "H" -or $val -eq "h") { $wizard.Enabled = $false; $step++ }
                else { Write-Host "  [!] E veya H girin." -ForegroundColor Red }
            }

            # --- ADIM 15: Kurulum Sirasi ---
            15 {
                Write-Host "  Kurulum Sirasi (varsayilan: en son + 1)" -ForegroundColor Magenta
                Write-Host ("=" * 60) -ForegroundColor Magenta
                Write-Host "  [B]=Onceki Adim | [0]=Iptal | [Enter]=Varsayilan koru ($($wizard.InstallOrder))" -ForegroundColor DarkCyan
                Write-Host "  Mevcut: $($wizard.InstallOrder)" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  Kurulum Sirasi: " -ForegroundColor Yellow -NoNewline
                $val = Read-Host
                if ($val -eq "0") { Write-Host "  Ekleme iptal edildi." -ForegroundColor Red; return }
                if ($val -eq "B" -or $val -eq "b") { $step--; continue }
                if ($val -ne "") {
                    $num = 0
                    if ([int]::TryParse($val, [ref]$num) -and $num -gt 0) {
                        $wizard.InstallOrder = $num
                    } else {
                        Write-Host "  [!] Gecerli bir pozitif sayi girin." -ForegroundColor Red
                        continue
                    }
                }
                $step++
            }
        }
    }

    # --- OZET VE KAYIT ---
    while ($true) {
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "  OZET - KAYIT ONCESI KONTROL" -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host ""
        $summaryApp = [PSCustomObject]@{
            Name            = $wizard.Name
            Id              = $wizard.Id
            Publisher       = $wizard.Publisher
            Category        = $wizard.Category
            Description     = $wizard.Description
            Website         = $wizard.Website
            Source          = $wizard.Source
            Architecture    = $wizard.Architecture
            Scope           = $wizard.Scope
            InstallType     = $wizard.InstallType
            SilentInstall   = $wizard.SilentInstall
            CustomArguments = $wizard.CustomArguments
            Version         = $wizard.Version
            Enabled         = $wizard.Enabled
            InstallOrder    = $wizard.InstallOrder
        }
        Show-ApplicationDetail -App $summaryApp

        Write-Host "  [1] Kaydet" -ForegroundColor Green
        Write-Host "  [2] Bastan Duzenle" -ForegroundColor Yellow
        Write-Host "  [0] Iptal" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Secim: " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host

        switch ($choice) {
            "1" {
                # Atomik kayit
                $appList = [System.Collections.ArrayList]@($data.applications)
                $newApp = [PSCustomObject]@{
                    Id              = $wizard.Id
                    Name            = $wizard.Name
                    Publisher       = $wizard.Publisher
                    Description     = $wizard.Description
                    Category        = $wizard.Category
                    Website         = $wizard.Website
                    InstallType     = $wizard.InstallType
                    Architecture    = $wizard.Architecture
                    Scope           = $wizard.Scope
                    SilentInstall   = $wizard.SilentInstall
                    CustomArguments = $wizard.CustomArguments
                    Version         = $wizard.Version
                    Enabled         = $wizard.Enabled
                    InstallOrder    = $wizard.InstallOrder
                    Source          = $wizard.Source
                }
                $appList.Add($newApp) | Out-Null
                $data.applications = $appList.ToArray()

                $result = Save-CatalogData -Data $data
                if ($result -ne $false) {
                    Write-Host ""
                    Write-Host ("=" * 60) -ForegroundColor Green
                    Write-Host "  [OK] '$($wizard.Name)' basariyla kataloga eklendi!" -ForegroundColor Green
                    Write-Host ("=" * 60) -ForegroundColor Green
                }
                return
            }
            "2" {
                # Wizard'i bastan baslatma icin step=1'e don
                $step = 1
                break
            }
            "0" {
                Write-Host "  Ekleme iptal edildi." -ForegroundColor Red
                return
            }
            default {
                Write-Host "  [!] Gecersiz secim. 0, 1 veya 2 girin." -ForegroundColor Red
            }
        }

        # Eger "Bastan Duzenle" secildi ise wizard'a don
        if ($choice -eq "2") {
            # Wizard dongusu bastan
            while ($step -le $totalSteps) {
                # Bu invoke, recursive yerine goto'yu taklit etmek icin
                # Fonksiyonu yeniden cagir
                break
            }
            # Yeniden girmeyi saglamak icin dis while dongusunu kiriyoruz
            # ve fonksiyonu yeniden cagiriyoruz
            Invoke-AddApplication
            return
        }
    }
}

#endregion

#region --- PROGRAM DUZENLEME: Invoke-EditApplication ---

function Invoke-EditApplication {
    <#
    .SYNOPSIS
        Mevcut programi duzenler.
    #>
    Show-CatalogHeader -Title "Program Duzenle"

    $data = Get-CatalogData
    if (-not $data) {
        Write-Host "  [HATA] Katalog verisi yuklenemedi." -ForegroundColor Red
        return
    }

    $apps = @($data.applications)
    if ($apps.Count -eq 0) {
        Write-Host "  Katalogda kayitli program bulunmuyor." -ForegroundColor Yellow
        return
    }

    # Program sec
    $selectedApp = Select-ApplicationFromList -Applications $apps -Prompt "Duzenlenecek programin numarasini girin"
    if (-not $selectedApp) {
        Write-Host "  Duzenleme iptal edildi." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  Secilen Program: $($selectedApp.Name)" -ForegroundColor Green
    Show-ApplicationDetail -App $selectedApp

    # Alan secimi
    $fieldMap = @{
        1  = @{ Name = "Program Adi";           Prop = "Name";            Required = $true  }
        2  = @{ Name = "WinGet ID";             Prop = "Id";              Required = $true  }
        3  = @{ Name = "Yayinci";               Prop = "Publisher";       Required = $true  }
        4  = @{ Name = "Kategori";              Prop = "Category";        Required = $true  }
        5  = @{ Name = "Aciklama";              Prop = "Description";     Required = $false }
        6  = @{ Name = "Web Sitesi";            Prop = "Website";         Required = $false }
        7  = @{ Name = "Paket Kaynagi";         Prop = "Source";          Required = $true  }
        8  = @{ Name = "Mimari";                Prop = "Architecture";    Required = $true  }
        9  = @{ Name = "Kapsam";                Prop = "Scope";           Required = $true  }
        10 = @{ Name = "Kurulum Turu";          Prop = "InstallType";     Required = $true  }
        11 = @{ Name = "Sessiz Kurulum";        Prop = "SilentInstall";   Required = $true  }
        12 = @{ Name = "Ozel Parametreler";     Prop = "CustomArguments"; Required = $false }
        13 = @{ Name = "Surum";                 Prop = "Version";         Required = $true  }
        14 = @{ Name = "Etkin";                 Prop = "Enabled";         Required = $true  }
        15 = @{ Name = "Kurulum Sirasi";        Prop = "InstallOrder";    Required = $true  }
    }

    while ($true) {
        Write-Host "  Hangi alan degistirilsin? (1-15) [0=Iptal]: " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host
        if ($choice -eq "0" -or $choice -eq "") {
            Write-Host "  Duzenleme iptal edildi." -ForegroundColor Red
            return
        }

        $num = 0
        if (-not ([int]::TryParse($choice, [ref]$num) -and $fieldMap.ContainsKey($num))) {
            Write-Host "  [!] Gecersiz secim. 1 ile 15 arasinda bir deger girin." -ForegroundColor Red
            continue
        }

        $field = $fieldMap[$num]
        $prop  = $field.Prop
        $oldValue = $selectedApp.$prop

        Write-Host ""
        Write-Host "  Alan   : $($field.Name)" -ForegroundColor Cyan
        Write-Host "  Mevcut : $oldValue" -ForegroundColor Cyan
        Write-Host ""

        $newValue = $null

        switch ($prop) {
            "Source" {
                $opts = @("winget", "msstore", "other")
                $i = 1; foreach ($o in $opts) { Write-Host "  [$i] $o"; $i++ }
                Write-Host "  Secim [1-3]: " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                $n = 0
                if ([int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 3) {
                    $newValue = $opts[$n - 1]
                } else { Write-Host "  [!] Gecersiz." -ForegroundColor Red; continue }
            }
            "Architecture" {
                $opts = @("x64", "x86", "arm64", "any")
                $i = 1; foreach ($o in $opts) { Write-Host "  [$i] $o"; $i++ }
                Write-Host "  Secim [1-4]: " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                $n = 0
                if ([int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 4) {
                    $newValue = $opts[$n - 1]
                } else { Write-Host "  [!] Gecersiz." -ForegroundColor Red; continue }
            }
            "Scope" {
                $opts = @("machine", "user")
                $i = 1; foreach ($o in $opts) { Write-Host "  [$i] $o"; $i++ }
                Write-Host "  Secim [1-2]: " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                $n = 0
                if ([int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 2) {
                    $newValue = $opts[$n - 1]
                } else { Write-Host "  [!] Gecersiz." -ForegroundColor Red; continue }
            }
            "InstallType" {
                $opts = @("standard", "portable", "other")
                $i = 1; foreach ($o in $opts) { Write-Host "  [$i] $o"; $i++ }
                Write-Host "  Secim [1-3]: " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                $n = 0
                if ([int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 3) {
                    $newValue = $opts[$n - 1]
                } else { Write-Host "  [!] Gecersiz." -ForegroundColor Red; continue }
            }
            { $_ -in @("SilentInstall", "Enabled") } {
                Write-Host "  [E] Evet / [H] Hayir: " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                if ($v -eq "E" -or $v -eq "e") { $newValue = $true }
                elseif ($v -eq "H" -or $v -eq "h") { $newValue = $false }
                else { Write-Host "  [!] E veya H girin." -ForegroundColor Red; continue }
            }
            "InstallOrder" {
                Write-Host "  Yeni Deger (sayi): " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                $n = 0
                if ([int]::TryParse($v, [ref]$n) -and $n -gt 0) {
                    $newValue = $n
                } else { Write-Host "  [!] Gecerli bir pozitif sayi girin." -ForegroundColor Red; continue }
            }
            "Category" {
                $cats = @($data.categories)
                $i = 1
                foreach ($cat in $cats) {
                    Write-Host ("  [{0}] {1} {2}" -f $i, $cat.icon, $cat.name) -ForegroundColor White
                    $i++
                }
                Write-Host "  Secim [1-$($cats.Count)]: " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                $n = 0
                if ([int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le $cats.Count) {
                    $newValue = $cats[$n - 1].id
                } else { Write-Host "  [!] Gecersiz secim." -ForegroundColor Red; continue }
            }
            "Id" {
                Write-Host "  Yeni WinGet ID: " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                if ($v -eq "" -and $field.Required) { Write-Host "  [!] Bu alan bos birakilamaz." -ForegroundColor Red; continue }
                # Tekrar kontrolu
                $existing = $data.applications | Where-Object { $_.Id -eq $v -and $_.Id -ne $selectedApp.Id }
                if ($existing) {
                    Write-Host "  [!] Bu WinGet ID zaten katalogda: $($existing.Name)" -ForegroundColor Red
                    continue
                }
                $newValue = $v
            }
            default {
                Write-Host "  Yeni Deger: " -ForegroundColor Yellow -NoNewline
                $v = Read-Host
                if ($v -eq "" -and $field.Required) { Write-Host "  [!] Bu alan bos birakilamaz." -ForegroundColor Red; continue }
                $newValue = $v
            }
        }

        # Karsilastirma goster ve onay al
        Write-Host ""
        Write-Host "  DEGISIKLIK OZETI:" -ForegroundColor Cyan
        Write-Host ("  {0,-25}: {1} --> {2}" -f $field.Name, $oldValue, $newValue) -ForegroundColor White
        Write-Host ""
        Write-Host "  Kaydet? [E/H]: " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host

        if ($confirm -eq "E" -or $confirm -eq "e") {
            # Guncelle
            $selectedApp.$prop = $newValue
            # JSON'da bul ve guncelle
            $idx = -1
            for ($i = 0; $i -lt $data.applications.Count; $i++) {
                if ($data.applications[$i].Id -eq $selectedApp.Id) { $idx = $i; break }
            }
            if ($idx -ge 0) { $data.applications[$idx] = $selectedApp }

            $result = Save-CatalogData -Data $data
            if ($result -ne $false) {
                Write-Host "  [OK] '$($selectedApp.Name)' guncellendi!" -ForegroundColor Green
            }

            # Devam et mi?
            Write-Host ""
            Write-Host "  Baska bir alan duzenlemek istiyor musunuz? [E/H]: " -ForegroundColor Yellow -NoNewline
            $cont = Read-Host
            if ($cont -ne "E" -and $cont -ne "e") { return }
        } else {
            Write-Host "  Degisiklik iptal edildi." -ForegroundColor Yellow
        }
    }
}

#endregion

#region --- PROGRAM SILME: Invoke-DeleteApplication & Alt Fonksiyonlar ---

function Invoke-DeleteApplication {
    <#
    .SYNOPSIS
        Katalogdan tekli veya toplu program silme ana menusudur.
    #>
    while ($true) {
        Show-CatalogHeader -Title "Program Silme Yonetimi"

        Write-Host "  [1] | Tekli Program Sil (Katalogdan)" -ForegroundColor Yellow
        Write-Host "  [2] | Toplu Program Sil (Katalogdan)" -ForegroundColor Red
        Write-Host "  [0] | Geri Don" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  Seciminiz [0-2]: " -ForegroundColor Yellow -NoNewline
        $delChoice = Read-Host
        $ch = if ($null -ne $delChoice) { $delChoice.Trim() } else { "" }

        switch ($ch) {
            "1" { Invoke-DeleteSingleApplication; break }
            "2" { Invoke-BulkDeleteApplication; break }
            { $_ -in "0", "00", "" } { return }
            default {
                Write-Host "  [!] Gecersiz secim!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Invoke-DeleteSingleApplication {
    <#
    .SYNOPSIS
        Katalogdan tek bir program siler.
    #>
    Show-CatalogHeader -Title "Tekli Program Sil"

    $data = Get-CatalogData
    if (-not $data) {
        Write-Host "  [HATA] Katalog verisi yuklenemedi." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    $apps = @($data.applications)
    if ($apps.Count -eq 0) {
        Write-Host "  Katalogda kayitli program bulunmuyor." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    # Program sec
    $selectedApp = Select-ApplicationFromList -Applications $apps -Prompt "Silinecek programin numarasini girin"
    if (-not $selectedApp) {
        Write-Host "  Silme islemi iptal edildi." -ForegroundColor DarkCyan
        Start-Sleep -Seconds 1
        return
    }

    # Detay goster
    Write-Host ""
    Write-Host "  SILINECEK PROGRAM:" -ForegroundColor Red
    Show-ApplicationDetail -App $selectedApp

    # Uyari mesaji
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host "  [UYARI] Bu islem YALNIZCA katalog kaydini siler." -ForegroundColor Red
    Write-Host "          Bilgisayardan kurulu program KALDIRILMAZ." -ForegroundColor Red
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-Host ""

    # Yedek olustur
    Write-Host "  Silme oncesi yedek olusturuluyor..." -ForegroundColor Yellow
    $appsJsonPath = Get-AppsJsonPath
    $backupResult = Backup-DataFile -FilePath $appsJsonPath
    if ($backupResult) {
        Write-Host "  [OK] Yedek olusturuldu." -ForegroundColor Green
    } else {
        Write-Host "  [!] Yedek olusturulamadi. Silme islemi devam edecek." -ForegroundColor Yellow
    }

    # Onay
    Write-Host ""
    Write-Host "  '$($selectedApp.Name)' programini katalogdan silmek istiyor musunuz? [E/H]: " -ForegroundColor Yellow -NoNewline
    $confirm = Read-Host
    $c = if ($null -ne $confirm) { $confirm.Trim().ToUpper() } else { "" }

    if ($c -notin @("E", "EVET", "Y", "YES")) {
        Write-Host "  Silme islemi iptal edildi." -ForegroundColor DarkCyan
        Start-Sleep -Seconds 1
        return
    }

    # Sil - Hem Id hem winget_id hem Name kontrolu ile guvenli eslesme
    $targetId = if ($selectedApp.Id) { "$($selectedApp.Id)".Trim() } elseif ($selectedApp.winget_id) { "$($selectedApp.winget_id)".Trim() } else { "" }
    $targetName = if ($selectedApp.Name) { "$($selectedApp.Name)".Trim() } else { "" }

    $newApps = [System.Collections.ArrayList]@($data.applications | Where-Object {
        $curId = if ($_.Id) { "$($_.Id)".Trim() } elseif ($_.winget_id) { "$($_.winget_id)".Trim() } else { "" }
        $curName = if ($_.Name) { "$($_.Name)".Trim() } else { "" }

        if ($targetId -and $curId) {
            return ($curId -ne $targetId)
        } else {
            return ($curName -ne $targetName)
        }
    })
    $data.applications = $newApps.ToArray()

    $result = Save-CatalogData -Data $data
    if ($result -ne $false) {
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "  [OK] '$($selectedApp.Name)' katalogdan basariyla silindi." -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green

        # Loglama
        $logId = if ($targetId) { $targetId } else { $targetName }
        $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] SILINDI: $logId | $($selectedApp.Name)"
        if ($script:LogFilePath) {
            Add-Content -Path $script:LogFilePath -Value $logMsg -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "  [HATA] Katalog dosyasi kaydedilemedi!" -ForegroundColor Red
    }

    Start-Sleep -Seconds 2
}

function Invoke-BulkDeleteApplication {
    <#
    .SYNOPSIS
        Katalogdan toplu program siler (virgul veya aralik ile coklu secim).
    #>
    Show-CatalogHeader -Title "Toplu Program Sil"

    $data = Get-CatalogData
    if (-not $data) {
        Write-Host "  [HATA] Katalog verisi yuklenemedi." -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    $apps = @($data.applications)
    if ($apps.Count -eq 0) {
        Write-Host "  Katalogda kayitli program bulunmuyor." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    Show-ApplicationList -Applications $apps -Title "Katalogdaki Programlar"

    Write-Host "  Silinecek program numaralarini virgul veya aralik ile girin (Orn: 1,3,5 veya 1-4 | 0=Iptal): " -ForegroundColor Yellow -NoNewline
    $inp = Read-Host
    if (-not $inp -or $inp.Trim() -in "0", "00") {
        Write-Host "  Toplu silme iptal edildi." -ForegroundColor DarkCyan
        Start-Sleep -Seconds 1
        return
    }

    $selectedApps = [System.Collections.Generic.List[PSCustomObject]]::new()
    $tokens = $inp -split '[,;\s]+'

    foreach ($t in $tokens) {
        if ($t -match '^(\d+)-(\d+)$') {
            $s = [int]$matches[1]; $e = [int]$matches[2]
            if ($s -le $e) {
                for ($k = $s; $k -le $e; $k++) {
                    if ($k -ge 1 -and $k -le $apps.Count) {
                        $candidate = $apps[$k - 1]
                        if (-not $selectedApps.Contains($candidate)) {
                            $selectedApps.Add($candidate)
                        }
                    }
                }
            }
        } elseif ($t -match '^\d+$') {
            $num = [int]$t
            if ($num -ge 1 -and $num -le $apps.Count) {
                $candidate = $apps[$num - 1]
                if (-not $selectedApps.Contains($candidate)) {
                    $selectedApps.Add($candidate)
                }
            }
        }
    }

    if ($selectedApps.Count -eq 0) {
        Write-Host "  [!] Gecerli program secilmedi." -ForegroundColor Red
        Start-Sleep -Seconds 1
        return
    }

    # Onay ve Secilenleri Listele
    Write-Host ""
    Write-Host "  SILINMEK UZERE SECILEN PROGRAMLAR ($($selectedApps.Count) Adet):" -ForegroundColor Red
    Write-Host ("-" * 60) -ForegroundColor Red
    $dIdx = 1
    foreach ($sa in $selectedApps) {
        $saId = if ($sa.Id) { $sa.Id } elseif ($sa.winget_id) { $sa.winget_id } else { "-" }
        Write-Host ("  {0,2}. {1,-35} ({2})" -f $dIdx, $sa.Name, $saId) -ForegroundColor White
        $dIdx++
    }
    Write-Host ("-" * 60) -ForegroundColor Red

    # Uyari
    Write-Host ""
    Write-Host "  [UYARI] Bu islem yalnizca katalog kayitlarini siler. Programlar bilgisayardan kaldirilmaz." -ForegroundColor Yellow
    Write-Host ""

    # Yedek olustur
    Write-Host "  Silme oncesi yedek olusturuluyor..." -ForegroundColor Yellow
    $appsJsonPath = Get-AppsJsonPath
    $backupResult = Backup-DataFile -FilePath $appsJsonPath
    if ($backupResult) {
        Write-Host "  [OK] Yedek olusturuldu." -ForegroundColor Green
    } else {
        Write-Host "  [!] Yedek olusturulamadi. Silme islemi devam edecek." -ForegroundColor Yellow
    }

    # Onay al
    Write-Host ""
    Write-Host "  Bu $($selectedApps.Count) programi katalogdan silmek istediginize EMIN MISINIZ? [E/H]: " -ForegroundColor Red -NoNewline
    $conf = Read-Host
    $cc = if ($null -ne $conf) { $conf.Trim().ToUpper() } else { "" }

    if ($cc -notin @("E", "EVET", "Y", "YES")) {
        Write-Host "  Toplu silme islemi iptal edildi." -ForegroundColor DarkCyan
        Start-Sleep -Seconds 1
        return
    }

    # Toplu ID & Name filtreleme kumesi
    $deleteIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $deleteNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($delApp in $selectedApps) {
        $dId = if ($delApp.Id) { "$($delApp.Id)".Trim() } elseif ($delApp.winget_id) { "$($delApp.winget_id)".Trim() } else { "" }
        if ($dId) { $null = $deleteIds.Add($dId) }
        if ($delApp.Name) { $null = $deleteNames.Add("$($delApp.Name)".Trim()) }
    }

    $newApps = [System.Collections.ArrayList]@($data.applications | Where-Object {
        $curId = if ($_.Id) { "$($_.Id)".Trim() } elseif ($_.winget_id) { "$($_.winget_id)".Trim() } else { "" }
        $curName = if ($_.Name) { "$($_.Name)".Trim() } else { "" }

        $matchId = if ($curId) { $deleteIds.Contains($curId) } else { $false }
        $matchName = if ($curName) { $deleteNames.Contains($curName) } else { $false }

        return (-not ($matchId -or $matchName))
    })

    $deletedCount = $data.applications.Count - $newApps.Count
    $data.applications = $newApps.ToArray()

    $result = Save-CatalogData -Data $data
    if ($result -ne $false) {
        Write-Host ""
        Write-Host ("=" * 60) -ForegroundColor Green
        Write-Host "  [OK] Toplam $deletedCount adet program katalogdan basariyla silindi." -ForegroundColor Green
        Write-Host ("=" * 60) -ForegroundColor Green

        # Loglama
        foreach ($delApp in $selectedApps) {
            $logId = if ($delApp.Id) { $delApp.Id } elseif ($delApp.winget_id) { $delApp.winget_id } else { $delApp.Name }
            $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] TOPLU SILINDI: $logId | $($delApp.Name)"
            if ($script:LogFilePath) {
                Add-Content -Path $script:LogFilePath -Value $logMsg -Encoding UTF8 -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-Host "  [HATA] Katalog dosyasi kaydedilemedi!" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  Devam etmek icin bir tusa basin..." -ForegroundColor DarkCyan
    $null = [Console]::ReadKey($true)
}

#endregion

#region --- KATEGORI YONETIMI: Invoke-CategoryManagement ---

function Invoke-CategoryManagement {
    <#
    .SYNOPSIS
        Kategori yonetimi alt menusu.
    #>
    while ($true) {
        Show-CatalogHeader -Title "Kategori Yonetimi"

        Write-Host "  [1] Kategori Listele" -ForegroundColor White
        Write-Host "  [2] Yeni Kategori Ekle" -ForegroundColor Green
        Write-Host "  [3] Kategori Adini Duzenle" -ForegroundColor Yellow
        Write-Host "  [4] Kategori Sil" -ForegroundColor Red
        Write-Host "  [5] Kategoriye Program Ata" -ForegroundColor Cyan
        Write-Host "  [0] Geri" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  Secim: " -ForegroundColor Yellow -NoNewline
        $choice = Read-Host

        switch ($choice) {
            "1" { Invoke-ListCategories }
            "2" { Invoke-AddCategory }
            "3" { Invoke-EditCategoryName }
            "4" { Invoke-DeleteCategory }
            "5" { Invoke-AssignAppToCategory }
            "0" { return }
            default { Write-Host "  [!] Gecersiz secim." -ForegroundColor Red }
        }

        if ($choice -ne "0") {
            Write-Host ""
            Write-Host "  Devam etmek icin [Enter]..." -ForegroundColor DarkCyan
            Read-Host | Out-Null
        }
    }
}

function Invoke-ListCategories {
    $data = Get-CatalogData
    if (-not $data) { Write-Host "  [HATA] Veri yuklenemedi." -ForegroundColor Red; return }

    Write-Host ""
    Write-Host ("-" * 60) -ForegroundColor DarkCyan
    Write-Host ("  {0,-5} {1,-6} {2,-25} {3}" -f "No", "Ikon", "Kategori Adi", "Program Sayisi") -ForegroundColor Cyan
    Write-Host ("-" * 60) -ForegroundColor DarkCyan

    $i = 1
    foreach ($cat in $data.categories) {
        $count = @($data.applications | Where-Object { $_.Category -eq $cat.id }).Count
        Write-Host ("  {0,-5} {1,-6} {2,-25} {3}" -f $i, $cat.icon, $cat.name, $count) -ForegroundColor White
        $i++
    }
    Write-Host ("-" * 60) -ForegroundColor DarkCyan
    Write-Host "  Toplam: $($data.categories.Count) kategori, $($data.applications.Count) program" -ForegroundColor Cyan
}

function Invoke-AddCategory {
    $data = Get-CatalogData
    if (-not $data) { Write-Host "  [HATA] Veri yuklenemedi." -ForegroundColor Red; return }

    Write-Host ""
    Write-Host "  Yeni Kategori Ekle" -ForegroundColor Green
    Write-Host ("-" * 40) -ForegroundColor DarkCyan

    Write-Host "  Kategori ID (kucuk harf, bosluksuz) [0=Iptal]: " -ForegroundColor Yellow -NoNewline
    $newId = Read-Host
    if ($newId -eq "0" -or $newId -eq "") { return }
    $newId = $newId.ToLower() -replace '\s', '_'

    # Tekrar kontrolu
    $existing = $data.categories | Where-Object { $_.id -eq $newId }
    if ($existing) {
        Write-Host "  [!] Bu ID zaten mevcut: $($existing.name)" -ForegroundColor Red
        return
    }

    Write-Host "  Kategori Adi [0=Iptal]: " -ForegroundColor Yellow -NoNewline
    $newName = Read-Host
    if ($newName -eq "0" -or $newName -eq "") { return }

    Write-Host "  Ikon (emoji, bos=paket ikonu): " -ForegroundColor Yellow -NoNewline
    $newIcon = Read-Host
    if ($newIcon -eq "") { $newIcon = "📦" }

    $newCat = [PSCustomObject]@{ id = $newId; name = $newName; icon = $newIcon }
    $catList = [System.Collections.ArrayList]@($data.categories)
    $catList.Add($newCat) | Out-Null
    $data.categories = $catList.ToArray()

    $result = Save-CatalogData -Data $data
    if ($result -ne $false) {
        Write-Host "  [OK] Kategori eklendi: $newIcon $newName (ID: $newId)" -ForegroundColor Green
    }
}

function Invoke-EditCategoryName {
    $data = Get-CatalogData
    if (-not $data) { Write-Host "  [HATA] Veri yuklenemedi." -ForegroundColor Red; return }

    $cats = @($data.categories)
    if ($cats.Count -eq 0) { Write-Host "  Hic kategori yok." -ForegroundColor Yellow; return }

    Invoke-ListCategories

    Write-Host "  Duzenlenecek kategori numarasi [0=Iptal]: " -ForegroundColor Yellow -NoNewline
    $val = Read-Host
    if ($val -eq "0" -or $val -eq "") { return }

    $num = 0
    if (-not ([int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le $cats.Count)) {
        Write-Host "  [!] Gecersiz secim." -ForegroundColor Red
        return
    }

    $selCat = $cats[$num - 1]
    Write-Host "  Mevcut Ad: $($selCat.name)" -ForegroundColor Cyan
    Write-Host "  Yeni Ad [0=Iptal]: " -ForegroundColor Yellow -NoNewline
    $newName = Read-Host
    if ($newName -eq "0" -or $newName -eq "") { return }

    $selCat.name = $newName

    $result = Save-CatalogData -Data $data
    if ($result -ne $false) {
        Write-Host "  [OK] Kategori adi guncellendi: $newName" -ForegroundColor Green
    }
}

function Invoke-DeleteCategory {
    $data = Get-CatalogData
    if (-not $data) { Write-Host "  [HATA] Veri yuklenemedi." -ForegroundColor Red; return }

    $cats = @($data.categories)
    if ($cats.Count -eq 0) { Write-Host "  Hic kategori yok." -ForegroundColor Yellow; return }

    Invoke-ListCategories

    Write-Host "  Silinecek kategori numarasi [0=Iptal]: " -ForegroundColor Yellow -NoNewline
    $val = Read-Host
    if ($val -eq "0" -or $val -eq "") { return }

    $num = 0
    if (-not ([int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le $cats.Count)) {
        Write-Host "  [!] Gecersiz secim." -ForegroundColor Red
        return
    }

    $selCat = $cats[$num - 1]
    $appsInCat = @($data.applications | Where-Object { $_.Category -eq $selCat.id })

    Write-Host ""
    Write-Host "  Silinecek: $($selCat.icon) $($selCat.name) (ID: $($selCat.id))" -ForegroundColor Red

    if ($appsInCat.Count -gt 0) {
        Write-Host ""
        Write-Host "  [UYARI] Bu kategoride $($appsInCat.Count) program var!" -ForegroundColor Red
        Write-Host "  Bu programlar baska bir kategoriye tasinabilir." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Ne yapmak istersiniz?" -ForegroundColor Yellow
        Write-Host "  [1] Programlari baska kategoriye tasi ve sil" -ForegroundColor White
        Write-Host "  [2] Programlari kategorisiz birak ve sil" -ForegroundColor White
        Write-Host "  [0] Iptal" -ForegroundColor DarkCyan
        Write-Host "  Secim: " -ForegroundColor Yellow -NoNewline
        $subChoice = Read-Host

        switch ($subChoice) {
            "1" {
                # Hedef kategori sec
                $remainingCats = @($cats | Where-Object { $_.id -ne $selCat.id })
                if ($remainingCats.Count -eq 0) {
                    Write-Host "  [!] Tasimak icin baska kategori yok." -ForegroundColor Red
                    return
                }
                Write-Host ""
                Write-Host "  Hedef kategori secin:" -ForegroundColor Cyan
                $j = 1
                foreach ($rc in $remainingCats) {
                    Write-Host ("  [{0}] {1} {2}" -f $j, $rc.icon, $rc.name) -ForegroundColor White
                    $j++
                }
                Write-Host "  Secim: " -ForegroundColor Yellow -NoNewline
                $tVal = Read-Host
                $tNum = 0
                if (-not ([int]::TryParse($tVal, [ref]$tNum) -and $tNum -ge 1 -and $tNum -le $remainingCats.Count)) {
                    Write-Host "  [!] Gecersiz secim." -ForegroundColor Red
                    return
                }
                $targetCat = $remainingCats[$tNum - 1]
                foreach ($app in $data.applications) {
                    if ($app.Category -eq $selCat.id) { $app.Category = $targetCat.id }
                }
                Write-Host "  [OK] $($appsInCat.Count) program '$($targetCat.name)' kategorisine tasindi." -ForegroundColor Green
            }
            "2" {
                foreach ($app in $data.applications) {
                    if ($app.Category -eq $selCat.id) { $app.Category = "" }
                }
                Write-Host "  [OK] $($appsInCat.Count) program kategorisiz birakildi." -ForegroundColor Yellow
            }
            "0" { return }
            default { Write-Host "  [!] Gecersiz secim." -ForegroundColor Red; return }
        }
    } else {
        Write-Host "  Bu kategoride program bulunmuyor." -ForegroundColor Cyan
        Write-Host "  Silmek istiyor musunuz? [E/H]: " -ForegroundColor Yellow -NoNewline
        $conf = Read-Host
        if ($conf -ne "E" -and $conf -ne "e") { return }
    }

    # Yedek
    $appsJsonPath = Get-AppsJsonPath
    Backup-DataFile -FilePath $appsJsonPath | Out-Null

    $newCats = [System.Collections.ArrayList]@($data.categories | Where-Object { $_.id -ne $selCat.id })
    $data.categories = $newCats.ToArray()

    $result = Save-CatalogData -Data $data
    if ($result -ne $false) {
        Write-Host "  [OK] '$($selCat.name)' kategorisi silindi." -ForegroundColor Green
    }
}

function Invoke-AssignAppToCategory {
    $data = Get-CatalogData
    if (-not $data) { Write-Host "  [HATA] Veri yuklenemedi." -ForegroundColor Red; return }

    $apps = @($data.applications)
    $cats = @($data.categories)

    if ($apps.Count -eq 0) { Write-Host "  Katalogda program yok." -ForegroundColor Yellow; return }
    if ($cats.Count -eq 0) { Write-Host "  Katalogda kategori yok." -ForegroundColor Yellow; return }

    Write-Host ""
    Write-Host "  Kategoriye Tasimak Istediginiz Programi Secin:" -ForegroundColor Cyan
    $selectedApp = Select-ApplicationFromList -Applications $apps -Prompt "Program numarasi"
    if (-not $selectedApp) { return }

    Write-Host ""
    Write-Host "  Mevcut Kategori: $($selectedApp.Category)" -ForegroundColor Cyan
    Write-Host "  Hedef Kategori Secin:" -ForegroundColor Cyan
    Write-Host ""

    $i = 1
    foreach ($cat in $cats) {
        $marker = if ($cat.id -eq $selectedApp.Category) { " <-- mevcut" } else { "" }
        Write-Host ("  [{0}] {1} {2}{3}" -f $i, $cat.icon, $cat.name, $marker) -ForegroundColor White
        $i++
    }
    Write-Host ""
    Write-Host "  Secim [0=Iptal]: " -ForegroundColor Yellow -NoNewline
    $val = Read-Host
    if ($val -eq "0" -or $val -eq "") { return }

    $num = 0
    if (-not ([int]::TryParse($val, [ref]$num) -and $num -ge 1 -and $num -le $cats.Count)) {
        Write-Host "  [!] Gecersiz secim." -ForegroundColor Red
        return
    }

    $targetCat = $cats[$num - 1]
    $oldCat    = $selectedApp.Category

    # Guncelle
    $idx = -1
    for ($i = 0; $i -lt $data.applications.Count; $i++) {
        if ($data.applications[$i].Id -eq $selectedApp.Id) { $idx = $i; break }
    }
    if ($idx -ge 0) { $data.applications[$idx].Category = $targetCat.id }

    $result = Save-CatalogData -Data $data
    if ($result -ne $false) {
        Write-Host "  [OK] '$($selectedApp.Name)' kategorisi: $oldCat --> $($targetCat.id)" -ForegroundColor Green
    }
}

#endregion

#region --- MODULE EXPORT ---

Export-ModuleMember -Function @(
    'Invoke-AddApplication',
    'Invoke-EditApplication',
    'Invoke-DeleteApplication',
    'Invoke-DeleteSingleApplication',
    'Invoke-BulkDeleteApplication',
    'Invoke-CategoryManagement',
    'Invoke-ListCategories',
    'Invoke-AddCategory',
    'Invoke-EditCategoryName',
    'Invoke-DeleteCategory',
    'Invoke-AssignAppToCategory',
    'Get-AppsJsonPath',
    'Get-CatalogData',
    'Save-CatalogData',
    'Show-CatalogHeader',
    'Show-ApplicationList',
    'Show-ApplicationDetail',
    'Select-ApplicationFromList',
    'Get-NextInstallOrder'
)

#endregion
