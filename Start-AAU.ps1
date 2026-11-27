& {
    $ErrorActionPreference = "Stop"

    $repoUrl = "https://github.com/ardaustunel55/AAU_Kurulum_Asistani/archive/refs/heads/master.zip"
    $shaUrl  = "https://api.github.com/repos/ardaustunel55/AAU_Kurulum_Asistani/commits/master"
    $installRoot = Join-Path $env:LOCALAPPDATA "AAU_Kurulum_Asistani"
    $tempRoot = Join-Path $env:TEMP ("AAU_Setup_" + [guid]::NewGuid().ToString("N"))

    function Start-AauApp {
        param([string]$RootDir)
        $cmdArgs = '/c call "{0}"' -f (Join-Path $RootDir "AAU.cmd")
        Start-Process -FilePath $env:ComSpec -ArgumentList $cmdArgs -WorkingDirectory $RootDir
    }

    function Get-RemoteMasterSha {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $resp = Invoke-RestMethod -Uri $shaUrl -Headers @{
                Accept       = "application/vnd.github.sha"
                "User-Agent" = "AAU-Kurulum-Asistani"
            } -TimeoutSec 5
            if ($resp -is [string] -and $resp.Trim().Length -ge 7) {
                return $resp.Trim()
            }
        } catch {}
        return $null
    }

    try {
        Write-Host ""
        Write-Host "====================================" -ForegroundColor Cyan
        Write-Host "       AAU KURULUM ASISTANI" -ForegroundColor Cyan
        Write-Host "====================================" -ForegroundColor Cyan

        $isInstalled = (Test-Path (Join-Path $installRoot "AAU.cmd")) -and
                       (Test-Path (Join-Path $installRoot "src\main.ps1"))

        $remoteSha = Get-RemoteMasterSha
        $commitFile = Join-Path $installRoot ".aau_commit"
        $localSha = if (Test-Path $commitFile) { (Get-Content $commitFile -Raw -ErrorAction SilentlyContinue).Trim() } else { "" }

        if ($isInstalled -and $remoteSha -and ($localSha -eq $remoteSha)) {
            Write-Host "[OK] AAU guncel surumde." -ForegroundColor Green
            Write-Host "[INFO] Uygulama baslatiliyor..." -ForegroundColor Cyan
            Start-AauApp -RootDir $installRoot
            return
        }

        if ($isInstalled) {
            Write-Host "[INFO] Yeni guncelleme kontrol edildi, son surum indiriliyor..." -ForegroundColor Yellow
        } elseif (Test-Path $installRoot) {
            throw "Kurulum klasoru mevcut ancak dosyalar eksik. Guvenlik nedeniyle uzerine yazilmadi: $installRoot"
        } else {
            Write-Host "[INFO] GitHub deposuna baglaniliyor..." -ForegroundColor Yellow
        }

        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        $zipPath = Join-Path $tempRoot "AAU.zip"
        $extractPath = Join-Path $tempRoot "Extract"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $repoUrl -OutFile $zipPath -UseBasicParsing

        Write-Host "[INFO] Proje arsivi aciliyor..." -ForegroundColor Yellow
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $projectFolder = Get-ChildItem -Path $extractPath -Directory |
            Where-Object {
                (Test-Path (Join-Path $_.FullName "AAU.cmd")) -and
                (Test-Path (Join-Path $_.FullName "src\main.ps1"))
            } |
            Select-Object -First 1

        if (-not $projectFolder) {
            throw "Indirilen arsivde AAU.cmd veya src\main.ps1 bulunamadi."
        }

        if ($isInstalled) {
            Write-Host "[INFO] Mevcut kurulum guncelleniyor (log ve yedekler korunuyor)..." -ForegroundColor Yellow
            $preserveDirs = @("logs", "reports", "data\backups")
            Get-ChildItem -Path $projectFolder.FullName -Force | ForEach-Object {
                $dest = Join-Path $installRoot $_.Name
                if ($_.PSIsContainer) {
                    if ($_.Name -in @("logs", "reports")) { return }
                    if ($_.Name -eq "data") {
                        New-Item -ItemType Directory -Path $dest -Force | Out-Null
                        Get-ChildItem -Path $_.FullName -Force | ForEach-Object {
                            if ($_.Name -ne "backups") {
                                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name) -Recurse -Force
                            }
                        }
                        return
                    }
                    Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
                } else {
                    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
                }
            }
        } else {
            Write-Host "[INFO] Kurulum klasoru hazirlaniyor..." -ForegroundColor Yellow
            $parent = Split-Path $installRoot -Parent
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
            Move-Item -LiteralPath $projectFolder.FullName -Destination $installRoot
        }

        if (-not (Test-Path (Join-Path $installRoot "src\main.ps1"))) {
            throw "Kurulum sonrasi ana program dosyasi dogrulanamadi."
        }

        if ($remoteSha) {
            Set-Content -LiteralPath $commitFile -Value $remoteSha -Encoding ASCII -Force
        }

        Write-Host "[OK] AAU basariyla hazirlandi." -ForegroundColor Green
        Write-Host "[INFO] Uygulama baslatiliyor..." -ForegroundColor Cyan
        Start-AauApp -RootDir $installRoot
    }
    catch {
        Write-Host ""
        Write-Host "[HATA] $($_.Exception.Message)" -ForegroundColor Red
    }
    finally {
        if (Test-Path $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
