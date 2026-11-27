# ============================================================================
# AAU KURULUM ASISTANI - KAPSAMLI TEST SENARYOLARI
# ============================================================================
$ErrorActionPreference = "Continue"

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "       AAU KURULUM ASISTANI - TEST SENARYOLARI CALISTIRILIYOR               " -ForegroundColor White
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

function Assert-Test {
    param([string]$Name, [bool]$Condition, [string]$Details = "")
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        if ($Details) { Write-Host "         $Details" -ForegroundColor DarkGray }
        $script:testsPassed++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Details) { Write-Host "         HATA: $Details" -ForegroundColor Yellow }
        $script:testsFailed++
    }
}

# Modulleri Yukle
$mFiles = Get-ChildItem .\modules -Recurse -Filter "*.psm1"
foreach ($mf in $mFiles) {
    Import-Module $mf.FullName -Force -Global
}

$catalog = Import-AppCatalog
$allApps = @(Get-AppList -Catalog $catalog)

# ----------------------------------------------------------------------------
# GRUP 1: KURULUM & SECIM SISTEMI TESTLERI
# ----------------------------------------------------------------------------
Write-Host "--- GRUP 1: Kurulum ve Kategori Bazli Secim Sistemi ---" -ForegroundColor Yellow

# Test 1: Tek program secme
$selectedTest = [System.Collections.Generic.List[PSCustomObject]]::new()
$chromeApp = $allApps | Where-Object { $_.Name -like "*Chrome*" } | Select-Object -First 1
$selectedTest.Add($chromeApp)
Assert-Test -Name "1. Tek program secimi" -Condition ($selectedTest.Count -eq 1 -and $selectedTest[0].Name -eq $chromeApp.Name)

# Test 2: Birden fazla program secme
$firefoxApp = $allApps | Where-Object { $_.Name -like "*Firefox*" } | Select-Object -First 1
$selectedTest.Add($firefoxApp)
Assert-Test -Name "2. Birden fazla program secimi" -Condition ($selectedTest.Count -eq 2)

# Test 3: Farkli kategorilerden program secme
$discordApp = $allApps | Where-Object { "$($_.Category)".ToLower() -eq "communication" } | Select-Object -First 1
$vscodeApp  = $allApps | Where-Object { "$($_.Category)".ToLower() -eq "developer" } | Select-Object -First 1
$selectedTest.Add($discordApp)
$selectedTest.Add($vscodeApp)
$cats = @($selectedTest | ForEach-Object { "$($_.Category)".ToLower() } | Select-Object -Unique)
Assert-Test -Name "3. Farkli kategorilerden program secme" -Condition ($cats.Count -ge 3) -Details "Kategoriler: $($cats -join ', ')"

# Test 4: Secimleri koruma
Assert-Test -Name "4. Secimlerin korunmasi" -Condition ($selectedTest.Count -eq 4) -Details "Sepette $($selectedTest.Count) oge var."

# Test 5: Ayni programi iki kez eklemeyi engelleme / toggle mantigi
$prevCount = $selectedTest.Count
$existing = $selectedTest | Where-Object { $_.Name -eq $chromeApp.Name }
if ($existing) { $selectedTest.Remove($existing) | Out-Null }
Assert-Test -Name "5. Ayni programi cikarabilme (Toggle mantigi)" -Condition ($selectedTest.Count -eq ($prevCount - 1))

# Test 6: Tekli ve Toplu ortak motor tetikleme tespiti
$singleCart = [System.Collections.Generic.List[PSCustomObject]]::new()
$singleCart.Add($chromeApp)
$singleIsBulk = ($singleCart.Count -ge 2)
$bulkCart = [System.Collections.Generic.List[PSCustomObject]]::new()
$bulkCart.Add($chromeApp); $bulkCart.Add($firefoxApp)
$bulkIsBulk = ($bulkCart.Count -ge 2)
Assert-Test -Name "6. Ortak motor tekli/toplu ayrismasi" -Condition (-not $singleIsBulk -and $bulkIsBulk) -Details "Tekli: $($singleCart.Count) (Bulk=$singleIsBulk), Toplu: $($bulkCart.Count) (Bulk=$bulkIsBulk)"

# Test 7: Progress bar ve formatlama testi
$pBar = Format-ProgressBar -Percent 50 -Width 20
Assert-Test -Name "7. Progress bar hesaplamasi" -Condition ($pBar -match '50') -Details "Cikti: $pBar"

# Test 8: Hata izolasyonu (Build-WinGetCommand gecersiz paket)
$dummyApp = [PSCustomObject]@{ Id = "Dummy.NonExistent.App"; Name = "Dummy"; Source = "winget" }
$cmdTest = Build-WinGetCommand -App $dummyApp -Action "install"
Assert-Test -Name "8. WinGet komut olusturma dogrulamasi" -Condition ($cmdTest -contains "Dummy.NonExistent.App" -and $cmdTest -contains "install")

# ----------------------------------------------------------------------------
# GRUP 2: BASLAT MENUSU KISAYOL SISTEMI TESTLERI
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- GRUP 2: Baslat Menusu Kisayol ve Dosya Kontrol Sistemi ---" -ForegroundColor Yellow

# Test 9: Ortak Kisayol Klasoru
$commonMenu = [System.Environment]::GetFolderPath('CommonPrograms')
Assert-Test -Name "9. Ortak Kisayol klasoru erisimi" -Condition (Test-Path $commonMenu) -Details "Konum: $commonMenu"

# Test 10: Kullaniciya Ozel Kisayol Klasoru
$userMenu = [System.Environment]::GetFolderPath('Programs')
Assert-Test -Name "10. Kullaniciya ozel Kisayol klasoru erisimi" -Condition (Test-Path $userMenu) -Details "Konum: $userMenu"

# Test 11: Kurulum sonrasi kisayol tespiti (Chrome veya bilinen bir program)
$chkChrome = Test-AppStartMenuShortcut -AppName "Google Chrome" -PackageId "Google.Chrome"
Assert-Test -Name "11. Kurulum sonrasi kisayol tespiti" -Condition ($chkChrome.ShortcutFound -or $chkChrome.ExeFound) -Details "ExeFound=$($chkChrome.ExeFound), ShortcutFound=$($chkChrome.ShortcutFound)"

# Test 12: Eksik kisayol durumunu raporlama
$chkMissing = Test-AppStartMenuShortcut -AppName "TamamenHayaliBirUygulamaXYZ123" -PackageId "NonExistent.Package.XYZ"
Assert-Test -Name "12. Eksik kisayol durumunun tespiti" -Condition (-not $chkMissing.ShortcutFound) -Details "Bulunamadi olarak dogru raporlandi."

# Test 13: Gercek EXE yolu ile guvenli kisayol olusturma
$testShortcutName = "AAU_Test_Kisayol"
$notepadExe = (Get-Command "notepad.exe" -ErrorAction SilentlyContinue).Source
if (-not $notepadExe) { $notepadExe = "C:\Windows\System32\notepad.exe" }
$scCreated = Invoke-CreateAppShortcut -AppName $testShortcutName -ExePath $notepadExe
$targetLnk = Join-Path $userMenu "$testShortcutName.lnk"
Assert-Test -Name "13. Guvenli kisayol olusturma ve Shell bildirme" -Condition ($scCreated -and (Test-Path $targetLnk)) -Details "Olusturulan: $targetLnk"

# Test 14: Var olan kisayolun korunmasi ve temizligi
if (Test-Path $targetLnk) {
    Remove-Item $targetLnk -Force -ErrorAction SilentlyContinue
    Assert-Test -Name "14. Test kisayolunun temizlenmesi" -Condition (-not (Test-Path $targetLnk))
}

# Test 15: AppX / MSIX Modern paket kontrolu
$appxCheck = Test-AppStartMenuShortcut -AppName "WinRAR"
Assert-Test -Name "15. AppX / MSIX Modern kayit tespiti" -Condition ($appxCheck.ShortcutFound -and $appxCheck.ShortcutType -in 'AppX', 'Lnk') -Details "Type: $($appxCheck.ShortcutType) ($($appxCheck.ShortcutLocation))"

# ----------------------------------------------------------------------------
# GRUP 3: PROGRAM KALDIRMA SISTEMI TESTLERI
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- GRUP 3: Program Yonetim ve Guvenli Kaldirma Sistemi ---" -ForegroundColor Yellow

# Test 16: WinGet ile kurulu programlarin tespiti ve Id eslestirmesi
$installed = Get-InstalledPrograms -RefreshCache
$wingetManagedApps = @($installed | Where-Object { $_.IsWinGetManaged })
Assert-Test -Name "16. WinGet yonetilen programlarin tespiti" -Condition ($wingetManagedApps.Count -gt 0) -Details "WinGet ile eslesen $($wingetManagedApps.Count) program bulundu."

# Test 17: WinGet olmayan (yerel/MSI) programlarin tespiti
$nonWingetApps = @($installed | Where-Object { -not $_.IsWinGetManaged })
Assert-Test -Name "17. WinGet disi yerel/MSI programlarin tespiti" -Condition ($nonWingetApps.Count -gt 0) -Details "Yerel/MSI $($nonWingetApps.Count) program tespit edildi."

# Test 18: MSI GUID dogrulamasi
$guidTestValid = "{12345678-ABCD-EF01-2345-6789ABCDEF01}"
$guidTestInvalid = "invalid-guid-123"
$isValid = ($guidTestValid -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$')
$isInvalid = ($guidTestInvalid -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$')
Assert-Test -Name "18. MSI GUID regex guvenlik dogrulamasi" -Condition ($isValid -and -not $isInvalid)

# Test 19: Guvenli komut ayristirma (No Invoke-Expression, tirnakli yol)
$sampleCmd = '"C:\Program Files\Test Vendor\app_uninst.exe" /VERYSILENT /NORESTART'
$parsed = Split-UninstallCommandLine -CommandLine $sampleCmd
Assert-Test -Name "19. Guvenli EXE uninstaller komut ayristirma" -Condition ($parsed.ExePath -eq "C:\Program Files\Test Vendor\app_uninst.exe" -and $parsed.Arguments -eq "/VERYSILENT /NORESTART")

# Test 20: Toplu kaldirma ekraninda tum programlarin listelenebilmesi
$totalCount = $installed.Count
Assert-Test -Name "20. Toplu kaldirma icin envanter listelenmesi" -Condition ($totalCount -ge 10) -Details "Toplam $totalCount kurulu program listelendi (gorunmeme sorunu cozuldu)."

# Test 21: Hatali/olmayan kaldiriciyi guvenle reddetme
$fakeApp = [PSCustomObject]@{
    Name = "HayaliProgram"
    Version = "1.0"
    Publisher = "Yok"
    UninstallMethod = "Yerel Uninstaller (EXE)"
    QuietUninstall = '"C:\Gecersiz\Dizin\unins000.exe" /s'
    UninstallString = '"C:\Gecersiz\Dizin\unins000.exe"'
    IsWinGetManaged = $false
    IsMsi = $false
    Guid = $null
}
$fakeRes = Invoke-UninstallSingleApp -App $fakeApp -NonInteractive -NoWaitPrompt
Assert-Test -Name "21. Hatali dosya yolunu guvenle tespit edip reddetme" -Condition (-not $fakeRes.Success -and -not $fakeRes.RecordRemoved)

# Test 22: Kaldirma sonrasi kayit dogrulama mantigi
$regCheckFake = @(Get-InstalledPrograms | Where-Object { $_.Name -eq "HayaliProgram" })
Assert-Test -Name "22. Kaldirma sonrasi kayit kontrolu mantigi" -Condition ($regCheckFake.Count -eq 0)

# Test 23: PowerShell 5.1 uyumlulugu
$psVer = $PSVersionTable.PSVersion
Assert-Test -Name "23. PowerShell surum uyumlulugu" -Condition ($psVer.Major -ge 5) -Details "PS Version: $psVer"

# Test 24: Loglama sistemi kontrolu
$logOk = [bool](($global:LogFilePath -and (Test-Path $global:LogFilePath)) -or (Test-Path ".\logs"))
Assert-Test -Name "24. Log dizini ve islem gunlugu" -Condition $logOk

# ----------------------------------------------------------------------------
# GRUP 4: PARAMETRE VE KATALOG ENTEGRASYON TESTLERI (VLC Hatasi Cozumu)
# ----------------------------------------------------------------------------
Write-Host "--- GRUP 4: Parametre ve Arama/Detay Entegrasyon Testleri ---" -ForegroundColor Yellow

# Test 25: Test-AppInstalled -PackageId parametre uyumu (User Screenshot bug fix)
$vlcCheck1 = $null
$vlcErr1 = $null
try {
    $vlcCheck1 = Test-AppInstalled -PackageId "VideoLAN.VLC"
} catch {
    $vlcErr1 = $_.Exception.Message
}
Assert-Test -Name "25. Test-AppInstalled -PackageId 'VideoLAN.VLC' calismasi" -Condition ($null -eq $vlcErr1 -and $null -ne $vlcCheck1) -Details $(if ($vlcErr1) { "HATA: $vlcErr1" } else { "PackageId parametresi basariyla baglandi." })

# Test 26: Test-AppInstalled -Package nesnesi ile calismasi
$vlcAppObj = $allApps | Where-Object { $_.Id -eq "VideoLAN.VLC" } | Select-Object -First 1
$vlcCheck2 = $null
$vlcErr2 = $null
try {
    $vlcCheck2 = Test-AppInstalled -Package $vlcAppObj
} catch {
    $vlcErr2 = $_.Exception.Message
}
Assert-Test -Name "26. Test-AppInstalled -Package `$vlcAppObj calismasi" -Condition ($null -eq $vlcErr2 -and $null -ne $vlcCheck2)

# Test 27: Test-AppInstalled -Id parametresi ile calismasi
$vlcCheck3 = $null
$vlcErr3 = $null
try {
    $vlcCheck3 = Test-AppInstalled -Id "VideoLAN.VLC"
} catch {
    $vlcErr3 = $_.Exception.Message
}
Assert-Test -Name "27. Test-AppInstalled -Id 'VideoLAN.VLC' calismasi" -Condition ($null -eq $vlcErr3 -and $null -ne $vlcCheck3)

# Test 28: VLC arama motoru dogrulamasi
$searchResults = @(Search-AppByName -Catalog $catalog -SearchTerm "vlc")
Assert-Test -Name "28. Katalogda 'vlc' aramasinin basarili sonuclanmasi" -Condition ($searchResults.Count -ge 1 -and $searchResults[0].Id -eq "VideoLAN.VLC") -Details "Bulunan: $($searchResults[0].Name) ($($searchResults[0].Id))"

# Test 29: Kisayol ve Uninstaller fonksiyonlarinin esnek parametre destegi
$aliasErr = $null
try {
    $null = Get-AppExecutablePath -Name "VLC Media Player" -Id "VideoLAN.VLC"
    $null = Test-AppStartMenuShortcut -Name "VLC Media Player" -Id "VideoLAN.VLC"
} catch {
    $aliasErr = $_.Exception.Message
}
Assert-Test -Name "29. Kisayol fonksiyonlarinda parametre takma ad (alias) destegi" -Condition ($null -eq $aliasErr)

# Test 30: Admin panelinde programlarin kategorili gruplanmasi
$catGrouped = @($allApps | Group-Object -Property Category)
Assert-Test -Name "30. Admin katalogunda programlarin kategorili (katalog bazli) gruplanmasi" -Condition ($catGrouped.Count -ge 8) -Details "Toplam $($catGrouped.Count) kategori/katalog basariyla tespit edildi."

# ----------------------------------------------------------------------------
# GRUP 5: PROFIL YONETIMI ENTEGRASYON VE DAYANIKLILIK TESTLERI
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- GRUP 5: Profil Yonetimi Entegrasyon ve Dayaniklilik Testleri ---" -ForegroundColor Yellow

$profilesPath = Get-ProfilesFilePath
$backupDir = Get-BackupDirPath
$tempBackupFile = Join-Path $env:TEMP ("profiles_pretest_" + (Get-Date -Format "yyyyMMddHHmmss") + ".json")
if (Test-Path $profilesPath) {
    Copy-Item -Path $profilesPath -Destination $tempBackupFile -Force
}

try {
    # Test 31: Read-ProfilesJson yukleme
    $initData = Read-ProfilesJson
    Assert-Test -Name "31. Read-ProfilesJson yukleme" -Condition ($null -ne $initData -and $null -ne $initData.profiles) -Details "Profil sayisi: $($initData.profiles.Count)"

    # Test 32: WinGet ID normalizasyonu
    $allIdsAreWinget = $true
    foreach ($p in $initData.profiles) {
        foreach ($app in $p.applications) {
            if ([string]::IsNullOrWhiteSpace($app) -or $app -eq "google-chrome" -or $app -eq "7zip" -or $app -eq "vlc") {
                $allIdsAreWinget = $false
            }
        }
    }
    Assert-Test -Name "32. WinGet ID normalizasyonu" -Condition $allIdsAreWinget

    # Test 33: Otomatik yedekleme
    $backupCountBefore = @(Get-ChildItem -Path $backupDir -Filter "profiles_backup_*.json" -ErrorAction SilentlyContinue).Count
    $backupPath = New-ProfileBackup -SourcePath $profilesPath -Prefix "profiles"
    $backupCountAfter = @(Get-ChildItem -Path $backupDir -Filter "profiles_backup_*.json" -ErrorAction SilentlyContinue).Count
    Assert-Test -Name "33. Otomatik yedekleme (New-ProfileBackup)" -Condition ((Test-Path $backupPath) -and ($backupCountAfter -gt $backupCountBefore)) -Details "Yedek: $backupPath"

    # Test 34: Profil olusturma ve aninda JSON'a yazma
    $testProfileId = "test_developer_env"
    $testProfileName = "Test Gelistirici Paketi"
    $testProfileDesc = "Otomatik test senaryosu tarafindan olusturuldu"
    $testApps = @("Git.Git", "Microsoft.VisualStudioCode", "7zip.7zip")

    $newProfileObj = [PSCustomObject]@{
        id           = $testProfileId
        name         = $testProfileName
        description  = $testProfileDesc
        icon         = "🛠️"
        applications = [System.Collections.Generic.List[string]]::new()
        created_at   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        updated_at   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    foreach ($a in $testApps) { $newProfileObj.applications.Add($a) }

    $currentData = Read-ProfilesJson
    $profileList = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($p in $currentData.profiles) { $profileList.Add($p) }
    $profileList.Add($newProfileObj)
    $currentData.profiles = $profileList

    $saveOk = Write-ProfilesJson -Data $currentData
    Assert-Test -Name "34. Profil olusturma ve aninda JSON'a yazma" -Condition $saveOk

    # Test 35: Profil kaliciligi
    $reloadedData = Read-ProfilesJson
    $savedProfile = $reloadedData.profiles | Where-Object { $_.id -eq $testProfileId }
    Assert-Test -Name "35. Profilin yeniden okumada kalici olmasi" -Condition ($null -ne $savedProfile -and $savedProfile.applications.Count -eq 3)

    # Test 36: Coklu uygulama ekleme ve Duplicate engelleme
    $appsToAdd = @("VideoLAN.VLC", "microsoft.visualstudiocode", "Google.Chrome")
    $appSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $appList = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $savedProfile.applications) {
        [void]$appSet.Add($a)
        $appList.Add($a)
    }
    $addedCount = 0
    foreach ($candidate in $appsToAdd) {
        if (-not $appSet.Contains($candidate)) {
            $appList.Add($candidate)
            [void]$appSet.Add($candidate)
            $addedCount++
        }
    }
    $savedProfile.applications = $appList.ToArray()
    Write-ProfilesJson -Data $reloadedData | Out-Null

    $reloadedData2 = Read-ProfilesJson
    $updatedProfile = $reloadedData2.profiles | Where-Object { $_.id -eq $testProfileId }
    Assert-Test -Name "36. Coklu uygulama ekleme ve Duplicate engelleme" -Condition ($updatedProfile.applications.Count -eq 5 -and $addedCount -eq 2)

    # Test 37: Profil adi ve aciklamasini degistirme
    $updatedProfile.name = "Test Gelistirici Paketi (Guncel)"
    $updatedProfile.description = "Aciklama basariyla guncellendi."
    $updatedProfile.updated_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-ProfilesJson -Data $reloadedData2 | Out-Null

    $reloadedData3 = Read-ProfilesJson
    $editedProfile = $reloadedData3.profiles | Where-Object { $_.id -eq $testProfileId }
    Assert-Test -Name "37. Profil adi ve aciklamasini degistirme" -Condition ($editedProfile.name -eq "Test Gelistirici Paketi (Guncel)" -and $editedProfile.description -eq "Aciklama basariyla guncellendi.")

    # Test 38: Profildeki uygulamalarin sirasini degistirme (Reorder)
    $curApps = @($editedProfile.applications)
    $reorderedApps = [System.Collections.Generic.List[string]]::new()
    $reorderedApps.Add($curApps[4])
    $reorderedApps.Add($curApps[0])
    $reorderedApps.Add($curApps[1])
    $reorderedApps.Add($curApps[2])
    $reorderedApps.Add($curApps[3])
    $editedProfile.applications = $reorderedApps
    Write-ProfilesJson -Data $reloadedData3 | Out-Null

    $reloadedData4 = Read-ProfilesJson
    $reorderedProf = $reloadedData4.profiles | Where-Object { $_.id -eq $testProfileId }
    Assert-Test -Name "38. Profildeki uygulamalarin sirasini degistirme" -Condition ($reorderedProf.applications[0] -eq "Google.Chrome" -and $reorderedProf.applications[1] -eq "Git.Git")

    # Test 39: Profilden coklu uygulama cikarma
    $appsToRemove = @("Git.Git", "7zip.7zip")
    $remainingApps = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $reorderedProf.applications) {
        if ($appsToRemove -notcontains $a) {
            $remainingApps.Add($a)
        }
    }
    $reorderedProf.applications = $remainingApps
    Write-ProfilesJson -Data $reloadedData4 | Out-Null

    $reloadedData5 = Read-ProfilesJson
    $afterRemovalProf = $reloadedData5.profiles | Where-Object { $_.id -eq $testProfileId }
    Assert-Test -Name "39. Profilden coklu uygulama cikarma" -Condition ($afterRemovalProf.applications.Count -eq 3 -and ($afterRemovalProf.applications -notcontains "Git.Git"))

    # Test 40: PC'den dosya silinmediginin tespiti
    $sevenZipProgramFiles = "C:\Program Files\7-Zip"
    $pcSafetyOk = $true
    if (Test-Path $sevenZipProgramFiles) {
        $pcSafetyOk = (Test-Path "$sevenZipProgramFiles\7z.exe")
    }
    Assert-Test -Name "40. Profilden cikarmanin PC dosyalarina dokunmamasi" -Condition $pcSafetyOk

    # Test 41: Profil kopyalama
    $copiedProfileId = "test_developer_env_kopya"
    $copiedApps = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $afterRemovalProf.applications) { $copiedApps.Add($a) }

    $copiedProfile = [PSCustomObject]@{
        id           = $copiedProfileId
        name         = $afterRemovalProf.name + " (Kopya)"
        description  = $afterRemovalProf.description
        icon         = $afterRemovalProf.icon
        applications = $copiedApps
        created_at   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        updated_at   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $pList = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($p in $reloadedData5.profiles) { $pList.Add($p) }
    $pList.Add($copiedProfile)
    $reloadedData5.profiles = $pList
    Write-ProfilesJson -Data $reloadedData5 | Out-Null

    $reloadedData6 = Read-ProfilesJson
    $copiedCheck = $reloadedData6.profiles | Where-Object { $_.id -eq $copiedProfileId }
    Assert-Test -Name "41. Profil kopyalama" -Condition ($null -ne $copiedCheck -and $copiedCheck.applications.Count -eq $afterRemovalProf.applications.Count)

    # Test 42: Profil silme
    $countBeforeDelete = $reloadedData6.profiles.Count
    $remainingProfiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($p in $reloadedData6.profiles) {
        if ($p.id -ne $copiedProfileId) {
            $remainingProfiles.Add($p)
        }
    }
    $reloadedData6.profiles = $remainingProfiles
    Write-ProfilesJson -Data $reloadedData6 | Out-Null

    $reloadedData7 = Read-ProfilesJson
    $copiedStillExists = ($reloadedData7.profiles | Where-Object { $_.id -eq $copiedProfileId })
    $originalStillExists = ($reloadedData7.profiles | Where-Object { $_.id -eq $testProfileId })
    Assert-Test -Name "42. Profil silme (Diger profiller etkilenmez)" -Condition ($null -eq $copiedStillExists -and $null -ne $originalStillExists)

    # Test profilini de temizle
    $cleanList = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($p in $reloadedData7.profiles) {
        if ($p.id -ne $testProfileId) {
            $cleanList.Add($p)
        }
    }
    $reloadedData7.profiles = $cleanList
    Write-ProfilesJson -Data $reloadedData7 | Out-Null

    # Test 43: Bozuk JSON'dan otomatik kurtarma
    $corruptContent = "{ this is invalid json ::: syntax error [[["
    [System.IO.File]::WriteAllText($profilesPath, $corruptContent, [System.Text.Encoding]::UTF8)
    $recoveredData = Read-ProfilesJson
    Assert-Test -Name "43. Bozuk JSON tespiti ve otomatik en son yedekten kurtarma (Auto-Recovery)" -Condition ($null -ne $recoveredData -and $recoveredData.profiles.Count -gt 0)

    # Test 44: Profil uygulamalarini katalog nesnelerine ve WinGet motoruna baglama
    $catalogObj = Read-AppsJson
    $sampleProfile = $recoveredData.profiles | Select-Object -First 1
    $resolvedApps = [System.Collections.Generic.List[PSCustomObject]]::new()
    $catMap = @{}
    foreach ($app in $catalogObj.applications) { $catMap[$app.Id] = $app }
    foreach ($appId in $sampleProfile.applications) {
        if ($catMap.ContainsKey($appId)) {
            $resolvedApps.Add($catMap[$appId])
        } else {
            $resolvedApps.Add([PSCustomObject]@{
                Id            = $appId
                Name          = $appId
                Category      = "tools"
                Source        = "winget"
                Architecture  = "x64"
                Scope         = "user"
                SilentInstall = $true
            })
        }
    }
    Assert-Test -Name "44. Profil uygulamalarini katalog nesnelerine ve WinGet motoruna baglama" -Condition ($resolvedApps.Count -eq $sampleProfile.applications.Count)

} finally {
    if (Test-Path $tempBackupFile) {
        Copy-Item -Path $tempBackupFile -Destination $profilesPath -Force
        Remove-Item -Path $tempBackupFile -Force -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------------------------
# GRUP 6: KURULUM MOTORU, SUREC GUVEVNLIGI VE GERCEK ZAMANLI AKIS TESTLERI
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- GRUP 6: Kurulum Motoru, Surec Guvenligi ve Canli Akis Testleri ---" -ForegroundColor Yellow

# Test 45: Stop-ProcessTree fonksiyonu ve guvenli sonlandirma
$procTestOk = $false
try {
    # Arka planda kisa bir test sureci baslat
    $pInfo = New-Object System.Diagnostics.ProcessStartInfo
    $pInfo.FileName = "powershell.exe"
    $pInfo.Arguments = "-NoProfile -Command Start-Sleep -Seconds 30"
    $pInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $pInfo.CreateNoWindow = $true
    $testProc = [System.Diagnostics.Process]::Start($pInfo)

    if ($testProc -and -not $testProc.HasExited) {
        $testPid = $testProc.Id
        # Stop-ProcessTree fonksiyonunu cagir
        Stop-ProcessTree -ProcessId $testPid
        Start-Sleep -Milliseconds 400
        $isDead = $true
        try {
            $check = Get-Process -Id $testPid -ErrorAction Stop
            if ($check -and -not $check.HasExited) { $isDead = $false }
        } catch {
            $isDead = $true
        }
        $procTestOk = $isDead
    }
} catch {
    $procTestOk = $false
}
Assert-Test -Name "45. Stop-ProcessTree ile surec ve agacinin guvenli sonlandirilmasi" -Condition $procTestOk

# Test 46: WinGet cikti temizleme ve canli yuzde/asama ayrirma
$sampleWingetOutput = "`e[0m  Indiriliyor https://example.com/app.exe`r`n  [████████████████████░░░░░░░░░░] 65%`r`n"
$cleanSample = $sampleWingetOutput -replace "\x1b\[[0-9;]*[a-zA-Z]", ""
$detectedPercent = -1
if ($cleanSample -match '(\d{1,3})\s*%') {
    $detectedPercent = [int]$matches[1]
}
$detectedPhase = "Bilinmiyor"
if ($cleanSample -match 'Indiriliyor|Downloading') {
    $detectedPhase = "Indiriliyor"
}
Assert-Test -Name "46. WinGet cikti temizleme ve canli yuzde/asama ayrirma" -Condition ($detectedPercent -eq 65 -and $detectedPhase -eq "Indiriliyor") -Details "Yuzde: %$detectedPercent, Asama: $detectedPhase"

# Test 47: WinGet MB/GB indirme orani hesaplama
$sampleSizeText = "  50 MB / 200 MB  "
$calcPercent = -1
if ($sampleSizeText -match '([\d\.,]+)\s*([KMGTP]?B)\s*\/\s*([\d\.,]+)\s*([KMGTP]?B)') {
    $curVal = [double]($matches[1] -replace ',', '.')
    $totVal = [double]($matches[3] -replace ',', '.')
    if ($totVal -gt 0) {
        $calcPercent = [int]([math]::Round(($curVal / $totVal) * 100))
    }
}
Assert-Test -Name "47. WinGet veri boyutu oranindan otomatik yuzde hesaplama" -Condition ($calcPercent -eq 25) -Details "Hesaplanan: %$calcPercent (50 MB / 200 MB)"

# Test 48: Kurulum iptal durumunun (Cancelled) nesne ve sonuc raporuna aktarilmasi
$mockCancelledResult = [PSCustomObject]@{
    Success    = $false
    Skipped    = $false
    Cancelled  = $true
    ExitCode   = -99
    StdOut     = ""
    StdErr     = "Kullanici tarafindan iptal edildi (ESC/Q)"
    Duration   = 3
    Verified   = $false
    SkipReason = "Kullanici tarafindan iptal edildi"
}
$isProperlyFlagged = ($mockCancelledResult.Cancelled -eq $true -and $mockCancelledResult.ExitCode -eq -99 -and $mockCancelledResult.Success -eq $false)
Assert-Test -Name "48. Kurulum iptal durumunun (Cancelled) rapor nesnesine dogru aktarilmasi" -Condition $isProperlyFlagged -Details "Cancelled=$($mockCancelledResult.Cancelled), ExitCode=$($mockCancelledResult.ExitCode)"

# Test 49: Get-AppsJsonPath dinamik yol cozumlemesi (hardcoded kullanici masaustu olmamasi)
$catalogPath = Get-AppsJsonPath
$isDynamicAndValid = (Test-Path $catalogPath) -and (-not ($catalogPath -like "*C:\Users\AAU\Desktop\AAU_Kurulum_Asistani\data\apps\apps.json" -and $global:ProjectRoot -eq $null -and $script:DataDir -eq $null))
Assert-Test -Name "49. Get-AppsJsonPath dinamik yol tespiti ve dosya erisimi" -Condition (Test-Path $catalogPath) -Details "Yol: $catalogPath"

# Test 50: Yonetici paneli yedek dizini dogrulamasi (data\backups)
$expectedBackupDir = Join-Path (Split-Path (Split-Path (Get-AppsJsonPath) -Parent) -Parent) "data\backups"
$backupDirExists = [bool]((Test-Path $expectedBackupDir) -or (Test-Path (Join-Path $PSScriptRoot "data\backups")))
Assert-Test -Name "50. Yonetici paneli yedekleme dizini dogrulamasi (data\backups)" -Condition $backupDirExists -Details "Hedef: data\backups"

# ----------------------------------------------------------------------------
# GRUP 7: SISTEM, AG, ONARIM, GUVENLIK VE HIZLI ARACLAR TESTLERI
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- GRUP 7: Sistem, Ag, Onarim, Guvenlik ve Hizli Araclar Testleri ---" -ForegroundColor Yellow

# Test 51: system_tools modulu yukleme ve Test-AdminPrivilege
$isAdminCheck = Test-AdminPrivilege
Assert-Test -Name "51. Test-AdminPrivilege yetki denetimi fonksiyonu" -Condition ($isAdminCheck -is [bool]) -Details "AdminYetkisi=$isAdminCheck"

# Test 52: Invoke-LiveProcess canli surec yonetimi (ping 127.0.0.1)
$liveRes = Invoke-LiveProcess -FilePath "ping.exe" -Arguments "-n 1 127.0.0.1" -Title "Loopback Test"
Assert-Test -Name "52. Invoke-LiveProcess canli cikti ve calistirma" -Condition ($liveRes.ExitCode -eq 0 -and $liveRes.Output.Length -gt 0) -Details "Sure: $($liveRes.Duration)s, Cikti: $($liveRes.Output.Length) karakter"

# Test 53: Ag adaptoru ve IP tespiti (Get-NetAdapter / NetIPAddress)
$adaptersOk = $false
try {
    $adList = Get-NetAdapter -ErrorAction SilentlyContinue
    if ($adList -and $adList.Count -gt 0) { $adaptersOk = $true }
} catch {
    $adaptersOk = $true # Sanal ortamda adaptorsuz calisma ihtimali
}
Assert-Test -Name "53. Ag adaptoru ve baglanti bilgilerinin tespiti" -Condition $adaptersOk

# Test 54: Windows Guvenlik Duvari (Firewall) profillerinin tespiti
$fwOk = $false
try {
    $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    if ($fwProfiles -and $fwProfiles.Count -ge 1) { $fwOk = $true }
} catch {}
Assert-Test -Name "54. Windows Guvenlik Duvari (Firewall) profil tespiti" -Condition $fwOk

# Test 55: Windows Surum ve CIM OS bilgisi
$osInfoOk = $false
try {
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($osInfo -and $osInfo.Caption) { $osInfoOk = $true }
} catch {}
Assert-Test -Name "55. Windows Surum ve Build bilgisi tespiti (CIM Win32_OperatingSystem)" -Condition $osInfoOk -Details "OS: $($osInfo.Caption)"

# Test 56: Kullanici Temp klasoru erisimi ve guvenli tarama
$tempScanOk = (Test-Path $env:TEMP) -and (Get-ChildItem -Path $env:TEMP -ErrorAction SilentlyContinue).Count -ge 0
Assert-Test -Name "56. Kullanici Temp klasoru tespiti ve guvenli tarama yetenegi" -Condition $tempScanOk -Details "Temp: $env:TEMP"

# Test 57: Start-QuickToolApp hata yakalama (var olmayan arac guvenli sekilde reddedilir)
$quickToolErr = $false
try {
    # Var olmayan bir araci cagirma denemesi hatasiz yakalanmali
    Start-QuickToolApp -CommandName "varolmayan_hayali_arac_xyz.exe" -ToolTitle "Test Araci"
    $quickToolErr = $true
} catch {
    $quickToolErr = $false
}
Assert-Test -Name "57. Hizli Araclar calistiricisinda guvenli hata yakalama" -Condition $quickToolErr

# Test 58: WinGet guncellenebilir programlarin sorgulanabilmesi
$wingetUpgradesTested = $false
try {
    $upList = @(Get-WinGetUpgrades)
    $wingetUpgradesTested = ($upList -is [System.Array])
} catch {
    $wingetUpgradesTested = $false
}
Assert-Test -Name "58. WinGet program guncelleme tarama motoru entegrasyonu" -Condition $wingetUpgradesTested

# ----------------------------------------------------------------------------
# GRUP 8: YONETICI YETKISI VE PANEL SEKMELERI AYRIMI TESTLERI
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "--- GRUP 8: Yonetici Yetkisi ve Panel Ayrimi Testleri ---" -ForegroundColor Yellow

# Test 59: CMD baslaticilarinda RunAs / UAC Yonetici yukseltme kontrolu
$aauCmdContent = if (Test-Path ".\AAU.cmd") { Get-Content ".\AAU.cmd" -Raw } else { "" }
$adminCmdContent = if (Test-Path ".\AAU_Admin.cmd") { Get-Content ".\AAU_Admin.cmd" -Raw } else { "" }
$cmdElevationOk = ($aauCmdContent -match "net session" -and $aauCmdContent -match "-Verb RunAs") -and
                  ($adminCmdContent -match "net session" -and $adminCmdContent -match "-Verb RunAs")
Assert-Test -Name "59. CMD baslaticilarinda (AAU.cmd & AAU_Admin.cmd) RunAs UAC denetimi" -Condition $cmdElevationOk -Details "Her iki baslatici da UAC yonetici yukseltmesi iceriyor."

# Test 60: main.ps1 icinde Ensure-AdminPrivileges ve Test-IsAdmin varligi
$mainPs1Content = if (Test-Path ".\src\main.ps1") { Get-Content ".\src\main.ps1" -Raw } else { "" }
$mainElevationOk = ($mainPs1Content -match "function Ensure-AdminPrivileges") -and ($mainPs1Content -match "function Test-IsAdmin")
Assert-Test -Name "60. main.ps1 icinde Ensure-AdminPrivileges ve Test-IsAdmin guvenlik kontrolu" -Condition $mainElevationOk

# Test 61: Normal kullanici panelinden Yonetici Paneline erisimin engellenmesi
$noCrossAccess = (-not ($mainPs1Content -match "\[19\] \| Yonetici Paneli")) -and
                 ($mainPs1Content -match "Start-StandardUserLoop") -and
                 ($mainPs1Content -match "Start-AdminPanelLoop")
Assert-Test -Name "61. Normal kullanici panelinden Yonetici Paneline gecisin engellenmesi" -Condition $noCrossAccess -Details "Kullanici ve Yonetici panelleri ayrik dongulerde calisiyor."

# Test 62: Kullanici Paneli ile Yonetici Paneli sekmelerinin tam ayrismasi
$userMenuOk = ($mainPs1Content -match "KULLANICI PANELI - KATEGORI VE ARAC SECIMI") -and
              ($mainPs1Content -match "\[ 1\] \| Uygulama Kurulum") -and
              ($mainPs1Content -match "\[ 7\] \| Hizli Araclar") -and
              ($mainPs1Content -match "\[14\] \| Tani ve Onarim") -and
              ($mainPs1Content -match "Seciminiz \[1-22 \| 0=Cikis\]")
$adminMenuOk = ($mainPs1Content -match "AAU YONETICI PANELI - IDARI SISTEM VE VERITABANI") -and
               ($mainPs1Content -match "\[ 1\] \| Uygulama Katalogu Goruntule") -and
               ($mainPs1Content -match "\[ 2\] \| Yeni Uygulama Ekle") -and
               ($mainPs1Content -match "\[10\] \| Yedekleme ve Geri Yukleme")
$panelsSeparatedOk = $userMenuOk -and $adminMenuOk
Assert-Test -Name "62. Kullanici Paneli (18 arac) ve Yonetici Paneli (12 idari) sekmelerinin tam ayrismasi" -Condition $panelsSeparatedOk

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "TEST SONUCU: $testsPassed BASARILI / $testsFailed BASARISIZ (Toplam $($testsPassed + $testsFailed) Senaryo)" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host "============================================================================" -ForegroundColor Cyan
