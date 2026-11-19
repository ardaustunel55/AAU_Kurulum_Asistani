& {
    $ErrorActionPreference = "Stop"

    $repoUrl = "https://github.com/ardaustunel55/AAU_Kurulum_Asistani/archive/refs/heads/master.zip"
    $installRoot = Join-Path $env:LOCALAPPDATA "AAU_Kurulum_Asistani"
    $tempRoot = Join-Path $env:TEMP ("AAU_Setup_" + [guid]::NewGuid().ToString("N"))

    try {
        Write-Host ""
        Write-Host "====================================" -ForegroundColor Cyan
        Write-Host "       AAU KURULUM ASISTANI" -ForegroundColor Cyan
        Write-Host "====================================" -ForegroundColor Cyan

        # Mevcut kurulumu kontrol et
        if (Test-Path (Join-Path $installRoot "AAU.cmd")) {
            if (Test-Path (Join-Path $installRoot "src\main.ps1")) {
                Write-Host "[OK] AAU zaten kurulu." -ForegroundColor Green
                Write-Host "[INFO] Uygulama baslatiliyor..." -ForegroundColor Cyan

                $cmdArgs = '/c call "{0}"' -f (Join-Path $installRoot "AAU.cmd")
                Start-Process -FilePath $env:ComSpec -ArgumentList $cmdArgs -WorkingDirectory $installRoot
                return
            }
        }

        # Eksik veya bozuk kurulum klasorunu otomatik degistirme
        if (Test-Path $installRoot) {
            throw "Kurulum klasoru mevcut ancak dosyalar eksik. Guvenlik nedeniyle uzerine yazilmadi: $installRoot"
        }

        Write-Host "[INFO] GitHub deposuna baglaniliyor..." -ForegroundColor Yellow

        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        $zipPath = Join-Path $tempRoot "AAU.zip"
        $extractPath = Join-Path $tempRoot "Extract"

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

        Write-Host "[INFO] Kurulum klasoru hazirlaniyor..." -ForegroundColor Yellow

        $parent = Split-Path $installRoot -Parent
        New-Item -ItemType Directory -Path $parent -Force | Out-Null

        Move-Item -LiteralPath $projectFolder.FullName -Destination $installRoot

        if (-not (Test-Path (Join-Path $installRoot "src\main.ps1"))) {
            throw "Kurulum sonrasi ana program dosyasi dogrulanamadi."
        }

        Write-Host "[OK] AAU basariyla indirildi." -ForegroundColor Green
        Write-Host "[INFO] Uygulama baslatiliyor..." -ForegroundColor Cyan

        $cmdArgs = '/c call "{0}"' -f (Join-Path $installRoot "AAU.cmd")
        Start-Process -FilePath $env:ComSpec -ArgumentList $cmdArgs -WorkingDirectory $installRoot
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
