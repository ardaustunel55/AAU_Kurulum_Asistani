<#
.SYNOPSIS
    AAU Kurulum Asistani - Uygulama Katalogu Yonetim Modulu
.DESCRIPTION
    JSON tabanli uygulama katalogunu yukler, dogrular, listeler,
    filtreler, arar ve detay gosterir. Salt-okunur islemler ve
    detay ekranindan dogrudan kurulum cagirma ozellikleri sunar.
.NOTES
    PowerShell 5.1 uyumlu. Yonetici izni gerektirmez.
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

$script:CachedCatalogData     = $null
$script:CachedCatalogPath     = $null
$script:CachedCatalogLastWrite = $null

# ============================================================================
# IMPORT-APPCATALOG
# ============================================================================
function Import-AppCatalog {
<#
.SYNOPSIS
    data/apps/apps.json dosyasini yukler ve dogrular. Akilli onbellek (cache) ile gereksiz disk I/O yapmaz.
.OUTPUTS
    [PSCustomObject] Katalog nesnesi veya $null
#>
    param(
        [string]$CatalogPath,
        [switch]$ForceRefresh
    )

    if (-not $CatalogPath) {
        $root = if ($global:ProjectRoot) { $global:ProjectRoot }
                elseif ($script:ProjectRoot) { $script:ProjectRoot }
                else { (Get-Location).Path }
        $CatalogPath = Join-Path $root "data\apps\apps.json"
    }

    if (-not (Test-Path $CatalogPath)) {
        Write-LogError "Katalog dosyasi bulunamadi: $CatalogPath"
        Write-Host ""
        Write-Host "    [HATA] Uygulama katalog dosyasi bulunamadi!" -ForegroundColor Red
        Write-Host "    Beklenen konum: $CatalogPath" -ForegroundColor DarkCyan
        return $null
    }

    try {
        $fileInfo = Get-Item -LiteralPath $CatalogPath -ErrorAction Stop
        if (-not $ForceRefresh -and $script:CachedCatalogData -and $script:CachedCatalogPath -eq $CatalogPath -and $script:CachedCatalogLastWrite -eq $fileInfo.LastWriteTimeUtc) {
            return $script:CachedCatalogData
        }

        Write-LogInfo "Uygulama katalogu yukleniyor: $CatalogPath"
        $rawContent = [System.IO.File]::ReadAllText($CatalogPath, [System.Text.Encoding]::UTF8)
        $catalog = ConvertFrom-Json $rawContent

        if (-not $catalog) {
            Write-LogError "Katalog dosyasi bos veya gecersiz."
            Write-Host "    [HATA] Katalog dosyasi bos veya gecersiz!" -ForegroundColor Red
            return $null
        }

        if (-not $catalog.applications) {
            Write-LogError "Katalogda 'applications' alani bulunamadi."
            Write-Host "    [HATA] Katalog yapisi gecersiz: 'applications' alani eksik!" -ForegroundColor Red
            return $null
        }

        $script:CachedCatalogData = $catalog
        $script:CachedCatalogPath = $CatalogPath
        $script:CachedCatalogLastWrite = $fileInfo.LastWriteTimeUtc

        $appCount = @($catalog.applications).Count
        Write-LogSuccess "Katalog basariyla yuklendi: $appCount uygulama."
        return $catalog

    } catch {
        Write-LogError "JSON ayristirma hatasi: $($_.Exception.Message)"
        Write-Host ""
        Write-Host "    [HATA] Katalog dosyasi okunamadi veya JSON formati bozuk!" -ForegroundColor Red
        Write-Host "    Hata: $($_.Exception.Message)" -ForegroundColor DarkCyan
        return $null
    }
}

# ============================================================================
# GET-APPLIST
# ============================================================================
function Get-AppList {
<#
.SYNOPSIS
    Tum uygulamalari dondurur. Varsayilan olarak sadece Enabled olanlar.
    Elle eklenen uygulamalardaki sema farkliliklarina (winget_id, Enabled null vb.) tam toleranslidir.
#>
    param(
        [PSCustomObject]$Catalog,
        [switch]$IncludeDisabled
    )

    if (-not $Catalog -or -not $Catalog.applications) { return @() }

    $apps = @($Catalog.applications)
    if (-not $IncludeDisabled) {
        $apps = @($apps | Where-Object {
            $en = if ($null -ne $_.Enabled) { $_.Enabled }
                  elseif ($null -ne $_.enabled) { $_.enabled }
                  else { $true }
            $en -eq $true -or "$en".ToLower() -eq "true"
        })
    }

    # Guvenli siralama (InstallOrder sayisal yoksa 9999)
    $apps = @($apps | Sort-Object -Property @{
        Expression = {
            if ($null -ne $_.InstallOrder -and "$($_.InstallOrder)" -match '^\d+$') {
                [int]$_.InstallOrder
            } elseif ($null -ne $_.install_order -and "$($_.install_order)" -match '^\d+$') {
                [int]$_.install_order
            } else { 9999 }
        }
    }, @{ Expression = { "$($_.Name)" } })

    return $apps
}

# ============================================================================
# GET-APPSBYCATEGORY
# ============================================================================
function Get-AppsByCategory {
<#
.SYNOPSIS
    Belirli bir kategorideki uygulamalari InstallOrder sirasina gore dondurur.
#>
    param(
        [PSCustomObject]$Catalog,
        [string]$CategoryId,
        [switch]$IncludeDisabled
    )

    $allApps = Get-AppList -Catalog $Catalog -IncludeDisabled:$IncludeDisabled
    if (-not $CategoryId) { return $allApps }

    $targetCat = "$CategoryId".Trim().ToLower()
    $filtered = @($allApps | Where-Object {
        $cat = if ($_.Category) { "$($_.Category)".Trim().ToLower() }
               elseif ($_.category) { "$($_.category)".Trim().ToLower() }
               else { "" }
        $cat -eq $targetCat
    })
    return $filtered
}

# ============================================================================
# SEARCH-APPBYNAME
# ============================================================================
function Search-AppByName {
<#
.SYNOPSIS
    Uygulama adina, yayinciya, kimlige veya aciklamaya gore arama yapar.
#>
    param(
        [PSCustomObject]$Catalog,
        [string]$SearchTerm,
        [switch]$IncludeDisabled
    )

    if (-not $SearchTerm) { return @() }

    $allApps = Get-AppList -Catalog $Catalog -IncludeDisabled:$IncludeDisabled
    $results = @($allApps | Where-Object {
        $_.Name -like "*$SearchTerm*" -or
        $_.Publisher -like "*$SearchTerm*" -or
        $_.Description -like "*$SearchTerm*" -or
        $_.Id -like "*$SearchTerm*" -or
        $_.winget_id -like "*$SearchTerm*" -or
        $_.packageId -like "*$SearchTerm*"
    })
    return $results
}

# ============================================================================
# SEARCH-APPBYID
# ============================================================================
function Search-AppById {
<#
.SYNOPSIS
    WinGet ID veya Paket Kimligi uzerinden uygulama arar.
#>
    param(
        [PSCustomObject]$Catalog,
        [string]$AppId
    )

    if (-not $AppId -or -not $Catalog -or -not $Catalog.applications) { return $null }

    $targetId = "$AppId".Trim().ToLower()
    $found = @($Catalog.applications | Where-Object {
        ("$($_.Id)".Trim().ToLower() -eq $targetId) -or
        ("$($_.winget_id)".Trim().ToLower() -eq $targetId) -or
        ("$($_.packageId)".Trim().ToLower() -eq $targetId)
    })
    if ($found.Count -gt 0) { return $found[0] }
    return $null
}

# ============================================================================
# GET-APPDETAIL
# ============================================================================
function Get-AppDetail {
<#
.SYNOPSIS
    Bir uygulamanin tum detaylarini dondurur (index veya Id ile).
#>
    param(
        [PSCustomObject]$Catalog,
        [string]$AppId,
        [int]$Index = -1
    )

    if (-not $Catalog -or -not $Catalog.applications) { return $null }

    if ($Index -ge 0) {
        $enabledApps = @(Get-AppList -Catalog $Catalog)
        if ($Index -lt $enabledApps.Count) {
            return $enabledApps[$Index]
        }
        return $null
    }

    if ($AppId) {
        return Search-AppById -Catalog $Catalog -AppId $AppId
    }

    return $null
}

# ============================================================================
# GET-CATALOGSTATS
# ============================================================================
function Get-CatalogStats {
<#
.SYNOPSIS
    Katalog istatistiklerini hashtable olarak dondurur.
#>
    param([PSCustomObject]$Catalog)

    $stats = @{
        TotalApps     = 0
        EnabledApps   = 0
        DisabledApps  = 0
        Categories    = @()
        CategoryCount = 0
        WingetSource  = 0
        MsStoreSource = 0
        Unverified    = 0
    }

    if (-not $Catalog -or -not $Catalog.applications) { return $stats }

    $allApps = @($Catalog.applications)
    $stats.TotalApps    = $allApps.Count
    $stats.EnabledApps  = @($allApps | Where-Object { $_.Enabled -eq $true }).Count
    $stats.DisabledApps = @($allApps | Where-Object { $_.Enabled -ne $true }).Count
    $stats.WingetSource  = @($allApps | Where-Object { $_.Source -eq "winget" }).Count
    $stats.MsStoreSource = @($allApps | Where-Object { $_.Source -eq "msstore" }).Count
    $stats.Unverified    = @($allApps | Where-Object { $_.Enabled -ne $true }).Count

    $cats = @($allApps | Select-Object -ExpandProperty Category -Unique | Sort-Object)
    $stats.Categories    = $cats
    $stats.CategoryCount = $cats.Count

    return $stats
}

# ============================================================================
# GET-CATEGORYLIST
# ============================================================================
function Get-CategoryList {
<#
.SYNOPSIS
    Katalogdaki kategori listesini gosterim adiyla dondurur.
#>
    param([PSCustomObject]$Catalog)

    if (-not $Catalog -or -not $Catalog.categories) { return @() }
    return @($Catalog.categories)
}

# ============================================================================
# SHOW-APPLIST
# ============================================================================
function Show-AppList {
<#
.SYNOPSIS
    Tum uygulamalari Ghost Toolbox tarzinda kategorili, renkli ve 2 sutunlu duzende listeler.
#>
    param([PSCustomObject]$Catalog)

    Write-LogInfo "Tum uygulamalar kategorili ve renkli olarak listeleniyor."

    if (-not $Catalog) {
        $Catalog = Import-AppCatalog
    }

    if (-not $Catalog -or -not $Catalog.applications) {
        Write-Host ""
        Write-Host "    [HATA] Goruntulenecek uygulama katalogu bulunamadi." -ForegroundColor Red
        return
    }

    $allApps = @($Catalog.applications | Where-Object { $_.Enabled -eq $true })

    $colWidth = 41
    $lineSep = "-" * $colWidth

    function Format-AppListItem {
        param($app)
        $num = if ($app.InstallOrder -lt 10) { "[ $($app.InstallOrder)] |" } else { "[$($app.InstallOrder)] |" }
        $store = if ($app.Source -eq "msstore") { " [Store]" } else { "" }
        $name = $app.Name
        if ($name -like "*Visual C++*") { $name = "VC++ Redist 2015-2022 x64" }
        return "$num $name$store"
    }

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

    # Dinamik konsol genisligi tespiti
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

    if ($consWidth -ge 165) {
        $colCount = 6
    } elseif ($consWidth -ge 135) {
        $colCount = 5
    } elseif ($consWidth -ge 105) {
        $colCount = 4
    } else {
        $colCount = 3
    }

    $availWidth = [Math]::Max(84, ($consWidth - 4))
    $cellWidth = [Math]::Floor($availWidth / $colCount)
    $maxNameLen = [Math]::Max(14, ($cellWidth - 11))
    $bannerLen = [Math]::Max(86, [Math]::Min($consWidth - 2, ($cellWidth * $colCount + 2)))

    Write-Host ""
    Write-Host ("  :" + ("-" * ($bannerLen - 2)) + ":") -ForegroundColor DarkCyan
    $titleText = "AAU KURULUM ASISTANI - UYGULAMA KATALOGU"
    $titlePadLeft = [Math]::Max(0, [int](($bannerLen - $titleText.Length - 4) / 2))
    $titleLine = "  : " + (" " * $titlePadLeft) + $titleText
    Write-Host ($titleLine.PadRight($bannerLen + 1) + ":") -ForegroundColor Green
    Write-Host ("  :" + ("-" * ($bannerLen - 2)) + ":") -ForegroundColor DarkCyan

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
                    $ordStr = if ($app.InstallOrder -lt 10) { "[  $($app.InstallOrder)]" } elseif ($app.InstallOrder -lt 100) { "[ $($app.InstallOrder)]" } else { "[$($app.InstallOrder)]" }
                    $store = if ($app.Source -eq "msstore") { " *" } else { "" }
                    $name = $app.Name
                    if ($name -like "*Visual C++*") { $name = "VC++ Redist 2015-2022" }
                    if ($name.Length -gt $maxNameLen) { $name = $name.Substring(0, $maxNameLen - 3) + "..." }
                    $nameWithStore = "$name$store"
                    $namePad = $nameWithStore.PadRight($maxNameLen)

                    Write-Host $ordStr -ForegroundColor Yellow -NoNewline
                    Write-Host " | " -ForegroundColor DarkCyan -NoNewline
                    Write-Host $namePad -ForegroundColor White -NoNewline
                    
                    $padRemaining = $cellWidth - (6 + 3 + $maxNameLen)
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

    $msCount = @($allApps | Where-Object { $_.Source -eq "msstore" }).Count
    $wingetCount = $allApps.Count - $msCount

    Write-Host ""
    Write-Host ("  :" + ("-" * ($bannerLen - 2)) + ":") -ForegroundColor DarkCyan
    $infoText = "BILGI: Toplam {0} uygulama | {1} WinGet + {2} Store (*) | 8 Kategori" -f $allApps.Count, $wingetCount, $msCount
    Write-Host ("  :  " + $infoText.PadRight($bannerLen - 5) + ":") -ForegroundColor White
    $guideText = "Kurulum icin [ 1] Uygulama Kurulum Merkezi secenegini kullanabilirsiniz."
    Write-Host ("  :  " + $guideText.PadRight($bannerLen - 5) + ":") -ForegroundColor DarkCyan
    Write-Host ("  :" + ("-" * ($bannerLen - 2)) + ":") -ForegroundColor DarkCyan
    Write-Host ""
    Write-LogSuccess "Uygulama listesi dinamik coklu sutun formatinda gosterildi ($($allApps.Count) adet)."
}

# ============================================================================
# SHOW-APPSBYCATEGORY
# ============================================================================
function Show-AppsByCategory {
<#
.SYNOPSIS
    Kategori secimi yaptirir, o kategorideki uygulamalari listeler.
#>
    param([PSCustomObject]$Catalog)

    Write-LogInfo "Kategoriye gore uygulama listeleme baslatildi."

    $categories = Get-CategoryList -Catalog $Catalog

    if ($categories.Count -eq 0) {
        Write-Host ""
        Write-Host "    Katalogda kategori bilgisi bulunamadi." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  KATEGORILER" -ForegroundColor Green
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""

    $i = 1
    foreach ($cat in $categories) {
        $catApps = @(Get-AppsByCategory -Catalog $Catalog -CategoryId $cat.id)
        $num = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
        Write-Host "    $num " -ForegroundColor Green -NoNewline
        Write-Host "$($cat.icon) $($cat.name)" -ForegroundColor White -NoNewline
        Write-Host "  ($($catApps.Count) uygulama)" -ForegroundColor DarkCyan
        $i++
    }

    Write-Host ""
    Write-Host "    [ 0] |  Ana Menuye Don" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Kategori seciniz: " -ForegroundColor Yellow -NoNewline
    $inp = Read-Host
    $catChoice = if ($null -ne $inp) { $inp.Trim() } else { "" }

    if ($catChoice -eq "0" -or $catChoice -eq "00") { return }

    if ($catChoice -match "^\d+$") {
        $idx = [int]$catChoice
        if ($idx -ge 1 -and $idx -le $categories.Count) {
            $selectedCat = $categories[$idx - 1]
            $catApps = @(Get-AppsByCategory -Catalog $Catalog -CategoryId $selectedCat.id)

            Write-Host ""
            Write-Host "  $($selectedCat.icon) $($selectedCat.name)" -ForegroundColor Green
            Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
            Write-Host ""

            if ($catApps.Count -eq 0) {
                Write-Host "    Bu kategoride uygulama bulunamadi." -ForegroundColor Red
            } else {
                $j = 1
                foreach ($app in $catApps) {
                    $num = if ($j -lt 10) { "[ $j] |" } else { "[$j] |" }
                    $src = if ($app.Source -eq "msstore") { " [Store]" } else { "" }
                    Write-Host "    $num " -ForegroundColor Green -NoNewline
                    Write-Host "$($app.Name)" -ForegroundColor White -NoNewline
                    Write-Host "$src" -ForegroundColor DarkCyan -NoNewline
                    Write-Host "  ($($app.Id))" -ForegroundColor DarkCyan
                    $j++
                }
                Write-Host ""
                Write-Host "    Toplam: $($catApps.Count) uygulama." -ForegroundColor DarkCyan
            }
            Write-LogInfo "Kategori goruntulendi: $($selectedCat.name) ($($catApps.Count) uygulama)."
        } else {
            Write-Host "    [HATA] Gecersiz kategori secimi." -ForegroundColor Red
        }
    } else {
        Write-Host "    [HATA] Gecersiz giris." -ForegroundColor Red
    }
}

# ============================================================================
# SHOW-APPDETAILCARD (Interaktif Uygulama Karti)
# ============================================================================
function Show-AppDetailCard {
<#
.SYNOPSIS
    Bir uygulamanin ayrintili kartini cizer, sistem kurulum durumunu gosterir
    ve dogrudan kurulum veya web sitesini acma secenegi sunar.
#>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$App,
        [PSCustomObject]$Catalog
    )

    Write-Host ""
    Write-Host "  UYGULAMA DETAYLARI: $($App.Name)" -ForegroundColor Green
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""

    # Yerel Kurulum Durumu
    $isInstalled = $false
    $instVer = $null
    if (Get-Command "Test-AppInstalled" -ErrorAction SilentlyContinue) {
        try {
            $check = Test-AppInstalled -Package $App -Source $App.Source
            if ($check) {
                $isInstalled = [bool]$check.IsInstalled
                $instVer = $check.InstalledVersion
            }
        } catch {
            Write-LogWarn "Test-AppInstalled denetim hatasi: $($_.Exception.Message)"
        }
    }

    Write-Host "    Program Adi        : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Name)" -ForegroundColor White
    Write-Host "    Yayinci            : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Publisher)" -ForegroundColor White
    Write-Host "    Paket Kimligi (ID) : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Id)" -ForegroundColor Green
    Write-Host "    Kategori           : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Category)" -ForegroundColor White
    Write-Host "    Kaynak             : " -ForegroundColor DarkCyan -NoNewline
    if ($App.Source -eq "msstore") {
        Write-Host "$($App.Source) (Microsoft Store)" -ForegroundColor Cyan
    } else {
        Write-Host "$($App.Source) (WinGet Topluluk Deposu)" -ForegroundColor White
    }
    Write-Host "    Mimari             : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Architecture)" -ForegroundColor White
    Write-Host "    Kapsam (Scope)     : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Scope)" -ForegroundColor White
    Write-Host "    Sessiz Kurulum     : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.SilentInstall)" -ForegroundColor White
    Write-Host "    Surum (Katalog)    : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Version)" -ForegroundColor White
    Write-Host "    Kurulum Sirasi     : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.InstallOrder)" -ForegroundColor Yellow
    Write-Host "    Web Sitesi         : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Website)" -ForegroundColor DarkCyan
    Write-Host "    Aciklama           : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($App.Description)" -ForegroundColor White

    Write-Host ""
    Write-Host "    Sistem Kurulumu    : " -ForegroundColor DarkCyan -NoNewline
    if ($isInstalled) {
        $vStr = if ($instVer) { " (Surum: $instVer)" } else { "" }
        Write-Host "Kurulu$vStr" -ForegroundColor Green
    } else {
        Write-Host "Kurulu Degil" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host "  ISLEMLER:" -ForegroundColor DarkCyan
    Write-Host "    [1] Bu Programi Kur / Guncelle" -ForegroundColor Green
    if ($App.Website) {
        Write-Host "    [2] Web Sitesini Ac (Tarayicida)" -ForegroundColor Cyan
    }
    Write-Host "    [0] Geri Don" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Seciminiz: " -ForegroundColor Yellow -NoNewline
    $dChoice = Read-Host
    if ($dChoice -eq "1") {
        if (Get-Command "Invoke-WinGetInstall" -ErrorAction SilentlyContinue) {
            $res = Invoke-WinGetInstall -App $App
            if (Get-Command "Show-InstallReport" -ErrorAction SilentlyContinue) {
                Show-InstallReport -Results @(@{ App = $App; Result = $res }) -Title "TEKLI KURULUM SONUCU"
            }
            if (Get-Command "Wait-UserKeyPress" -ErrorAction SilentlyContinue) {
                Wait-UserKeyPress -PromptMessage "Devam etmek icin bir tusa basin..."
            }
        } else {
            Write-Host "  [HATA] Kurulum motoru yuklu degil!" -ForegroundColor Red
        }
    } elseif ($dChoice -eq "2" -and $App.Website) {
        try {
            Start-Process $App.Website
            Write-Host "  [BILGI] Tarayicida acildi: $($App.Website)" -ForegroundColor Green
            Start-Sleep -Seconds 1
        } catch {
            Write-Host "  [HATA] Tarayici acilamadi: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ============================================================================
# SHOW-APPSEARCHRESULTS
# ============================================================================
function Show-AppSearchResults {
<#
.SYNOPSIS
    Kullanicidan arama terimi alir, esilesen uygulamalari gosterir ve
    sonuclardan dogrudan secim/kurulum imkani sunar.
#>
    param([PSCustomObject]$Catalog)

    Write-LogInfo "Uygulama arama baslatildi."

    Write-Host ""
    Write-Host "  UYGULAMA ARAMA MOTORU" -ForegroundColor Green
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "    Aranacak program adi, yayinci, kategori veya ID yazin:" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "    Arama Terimi: " -ForegroundColor Yellow -NoNewline
    $inp = Read-Host
    $searchTerm = if ($null -ne $inp) { $inp.Trim() } else { "" }

    if (-not $searchTerm) {
        Write-Host "    Arama iptal edildi." -ForegroundColor DarkCyan
        return
    }

    Write-LogInfo "Uygulama arama terimi: '$searchTerm'"

    $results = @(Search-AppByName -Catalog $Catalog -SearchTerm $searchTerm)

    if ($results.Count -eq 0) {
        $byId = Search-AppById -Catalog $Catalog -AppId $searchTerm
        if ($byId) { $results = @($byId) }
    }

    Write-Host ""
    if ($results.Count -eq 0) {
        Write-Host "    '$searchTerm' icin katalogda sonuc bulunamadi." -ForegroundColor Red
        Write-LogInfo "Arama sonucsuz: '$searchTerm'"
    } else {
        Write-Host "  ARAMA SONUCLARI ('$searchTerm' - $($results.Count) sonuc):" -ForegroundColor Green
        Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
        Write-Host ""
        $i = 1
        foreach ($app in $results) {
            $num = if ($i -lt 10) { "[ $i] |" } else { "[$i] |" }
            $src = if ($app.Source -eq "msstore") { " [Store]" } else { " [WinGet]" }
            Write-Host "    $num " -ForegroundColor Green -NoNewline
            Write-Host "$($app.Name)".PadRight(28) -ForegroundColor White -NoNewline
            Write-Host "$src".PadRight(10) -ForegroundColor Cyan -NoNewline
            Write-Host "  ($($app.Id))" -ForegroundColor DarkCyan
            $i++
        }
        Write-Host ""
        Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
        Write-Host "  Detay incelemek veya kurmak icin bir numara secin [1-$($results.Count) | 0=Geri]: " -ForegroundColor Yellow -NoNewline
        $pick = Read-Host
        if ($pick -match '^\d+$') {
            $pIdx = [int]$pick
            if ($pIdx -ge 1 -and $pIdx -le $results.Count) {
                $chosen = $results[$pIdx - 1]
                Show-AppDetailCard -App $chosen -Catalog $Catalog
            }
        }
    }
}

# ============================================================================
# SHOW-APPDETAIL
# ============================================================================
function Show-AppDetail {
<#
.SYNOPSIS
    Interaktif olarak uygulama sectirir, detaylarini gosterir ve islem menusu sunar.
#>
    param([PSCustomObject]$Catalog)

    Write-LogInfo "Uygulama detay goruntuleme baslatildi."

    $apps = Get-AppList -Catalog $Catalog
    if ($apps.Count -eq 0) {
        Write-Host ""
        Write-Host "    Goruntulenecek uygulama bulunamadi." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  UYGULAMA DETAY GORUNTULEME" -ForegroundColor Green
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "    Detayini gormek istediginiz programin" -ForegroundColor DarkCyan
    Write-Host "    adini veya WinGet ID'sini yazin:" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "    Program Adi veya ID: " -ForegroundColor Yellow -NoNewline
    $inp = Read-Host
    $query = if ($null -ne $inp) { $inp.Trim() } else { "" }

    if (-not $query) {
        Write-Host "    Islem iptal edildi." -ForegroundColor DarkCyan
        return
    }

    # Once ID ile dene
    $app = Search-AppById -Catalog $Catalog -AppId $query

    # Bulunamazsa isimle ara
    if (-not $app) {
        $nameResults = @(Search-AppByName -Catalog $Catalog -SearchTerm $query -IncludeDisabled)
        if ($nameResults.Count -gt 0) { $app = $nameResults[0] }
    }

    if (-not $app) {
        Write-Host ""
        Write-Host "    '$query' ile eslesen uygulama bulunamadi." -ForegroundColor Red
        return
    }

    Show-AppDetailCard -App $app -Catalog $Catalog
}

# ============================================================================
# SHOW-CATALOGSTATS
# ============================================================================
function Show-CatalogStats {
<#
.SYNOPSIS
    Katalog istatistiklerini ve yerel kurulum metriklerini gosterir.
#>
    param([PSCustomObject]$Catalog)

    Write-LogInfo "Katalog istatistikleri goruntuleniyor."

    $stats = Get-CatalogStats -Catalog $Catalog

    Write-Host ""
    Write-Host "  KATALOG VE SISTEM KURULUM ISTATISTIKLERI" -ForegroundColor Green
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkCyan
    Write-Host ""

    Write-Host "    Toplam Katalog Uygulamasi : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($stats.TotalApps) adet" -ForegroundColor White

    Write-Host "    Aktif Kurulabilir         : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($stats.EnabledApps) adet" -ForegroundColor Green

    Write-Host "    Kategori Sayisi           : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($stats.CategoryCount) kategori" -ForegroundColor White

    Write-Host ""
    Write-Host "    Paket Kaynaklari:" -ForegroundColor DarkCyan
    Write-Host "      - WinGet Topluluk Deposu : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($stats.WingetSource) uygulama" -ForegroundColor White
    Write-Host "      - Microsoft Store        : " -ForegroundColor DarkCyan -NoNewline
    Write-Host "$($stats.MsStoreSource) uygulama" -ForegroundColor Cyan

    # Kategori dagilimi
    if ($Catalog -and $Catalog.categories) {
        Write-Host ""
        Write-Host "    Kategori Dagilimi:" -ForegroundColor DarkCyan
        foreach ($cat in $Catalog.categories) {
            $catApps = @(Get-AppsByCategory -Catalog $Catalog -CategoryId $cat.id)
            Write-Host "      $($cat.icon) " -NoNewline
            Write-Host "$($cat.name)".PadRight(35) -ForegroundColor White -NoNewline
            Write-Host ": $($catApps.Count) uygulama" -ForegroundColor DarkCyan
        }
    }

    # Yerel Kurulum Metrikleri
    if (Get-Command "Get-InstallHistory" -ErrorAction SilentlyContinue) {
        $history = Get-InstallHistory
        if ($history -and $history.Count -gt 0) {
            Write-Host ""
            Write-Host "    Yerel Kurulum Gecmisi Metrikleri:" -ForegroundColor Green
            $totalOps = $history.Count
            $succOps  = @($history | Where-Object { $_.Success -eq $true -and (-not $_.SkipReason) }).Count
            $skipOps  = @($history | Where-Object { $_.SkipReason }).Count
            $failOps  = @($history | Where-Object { $_.Success -eq $false }).Count
            $pct      = if ($totalOps -gt 0) { [Math]::Round(($succOps + $skipOps) / $totalOps * 100) } else { 0 }

            Write-Host "      Toplam Islem Sayisi      : " -ForegroundColor DarkCyan -NoNewline
            Write-Host "$totalOps" -ForegroundColor White
            Write-Host "      Basariyla Kurulan        : " -ForegroundColor DarkCyan -NoNewline
            Write-Host "$succOps" -ForegroundColor Green
            Write-Host "      Zaten Kurulu (Atlanan)   : " -ForegroundColor DarkCyan -NoNewline
            Write-Host "$skipOps" -ForegroundColor Yellow
            Write-Host "      Basarisiz Olan           : " -ForegroundColor DarkCyan -NoNewline
            Write-Host "$failOps" -ForegroundColor Red
            Write-Host "      Genel Basari Orani       : " -ForegroundColor DarkCyan -NoNewline
            Write-Host "%$pct" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-LogSuccess "Katalog istatistikleri gosterildi."
}

# ============================================================================
# MODUL DISA AKTARIM
# ============================================================================
Export-ModuleMember -Function @(
    'Import-AppCatalog',
    'Get-AppList',
    'Get-AppsByCategory',
    'Search-AppByName',
    'Search-AppById',
    'Get-AppDetail',
    'Get-CatalogStats',
    'Get-CategoryList',
    'Show-AppList',
    'Show-AppsByCategory',
    'Show-AppDetailCard',
    'Show-AppSearchResults',
    'Show-AppDetail',
    'Show-CatalogStats'
)
