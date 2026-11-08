# Snoophone : irm https://raw.githubusercontent.com/Snoog43/snoophone-releases/main/install.ps1 | iex
# Telecharge le dernier Snoophone-x64-setup.exe des releases de github.com/Snoog43/snoophone-releases, verifie son empreinte SHA256
# (publiee par GitHub) puis l'ouvre. Deja installe : l'installeur met a jour et relance Snoophone.
# Fichier en ASCII sans BOM : il est lu par irm puis execute par iex.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
# Les liens github.com/.../releases/download renvoient parfois 504 : on passe d'abord par l'API
# de GitHub (meme fichier), puis par le lien habituel, en reessayant.
function Get-File($url, $out, $apiUrl) {
    for ($try = 1; ; $try++) {
        try {
            if ($apiUrl) {
                try { Invoke-WebRequest $apiUrl -Headers @{ Accept = 'application/octet-stream' } -OutFile $out -UseBasicParsing -ErrorAction Stop; return } catch {}
            }
            Invoke-WebRequest $url -OutFile $out -UseBasicParsing -ErrorAction Stop; return
        }
        catch { if ($try -ge 4) { throw }; Start-Sleep -Seconds (2 * $try) }
    }
}
$rel = Invoke-RestMethod 'https://api.github.com/repos/Snoog43/snoophone-releases/releases/latest' -UseBasicParsing
$asset = @($rel.assets | Where-Object name -eq 'Snoophone-x64-setup.exe')[0]
if (-not $asset) { throw 'Snoophone-x64-setup.exe introuvable dans la derniere version.' }
$file = Join-Path $env:TEMP 'Snoophone-x64-setup.exe'
Write-Host "Snoophone $($rel.tag_name) : telechargement..." -ForegroundColor Cyan
Get-File $asset.browser_download_url $file $asset.url
if ("$($asset.digest)" -match '^sha256:([0-9a-f]{64})$' -and (Get-FileHash $file -Algorithm SHA256).Hash -ne $Matches[1]) {
    Remove-Item $file -Force
    throw 'Fichier abime pendant le telechargement (empreinte differente) : relancer la commande.'
}
Write-Host 'Ouverture de l''installeur : accepter la demande administrateur.' -ForegroundColor Cyan
Start-Process $file

# Telephone Android branche en USB (debogage USB actif) : y installe aussi l'appli.
# adb vient des platform-tools de Google, ranges la ou Snoophone les cherche ensuite.
$apkUrl = 'https://snoog43.github.io/snoophone-releases/Snoophone-android.apk'
try {
    # adb ecrit sur stderr ("daemon started...") : sous Windows PowerShell 5.1 ce ne doit pas etre une erreur.
    $ErrorActionPreference = 'Continue'
    $data = Join-Path $env:LOCALAPPDATA 'Snoophone'
    $adb = @((Join-Path $data 'platform-tools\adb.exe'),
             (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')) |
           Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $adb) { $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue; if ($cmd) { $adb = $cmd.Source } }
    if (-not $adb) {
        Write-Host 'Outils Android (adb) : telechargement...' -ForegroundColor Cyan
        New-Item -ItemType Directory -Force $data | Out-Null
        $zip = Join-Path $env:TEMP 'snoophone-platform-tools.zip'
        Get-File 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' $zip
        Expand-Archive $zip -DestinationPath $data -Force -ErrorAction Stop
        Remove-Item $zip -Force
        $adb = Join-Path $data 'platform-tools\adb.exe'
    }
    $serverWasUp = $false
    try { $t = New-Object Net.Sockets.TcpClient; $t.Connect('127.0.0.1', 5037); $t.Close(); $serverWasUp = $true } catch {}
    & $adb start-server 2>$null | Out-Null

    # Telephones branches par cable (pas les emulateurs ni le Wi-Fi) : serie -> etat.
    function Get-Phones {
        $list = @{}
        foreach ($line in (& $adb devices 2>$null)) {
            if ($line -match '^(\S+)\s+(device|unauthorized|offline|authorizing)$' -and $Matches[1] -notmatch '^emulator-|:|_adb-tls') {
                $list[$Matches[1]] = $Matches[2]
            }
        }
        $list
    }
    $phones = Get-Phones
    if ($phones.Count -eq 0) {
        Write-Host ''
        Write-Host 'Aucun telephone branche en USB (ou debogage USB eteint) : appli Android non installee.' -ForegroundColor Yellow
        Write-Host "Sur le telephone : $apkUrl" -ForegroundColor Yellow
        Write-Host 'Ou activer le debogage USB (Parametres > A propos > 7 appuis sur Numero de build, puis Options pour les developpeurs > Debogage USB), brancher le telephone et relancer cette commande.' -ForegroundColor Yellow
    } else {
        if (@($phones.Values | Where-Object { $_ -ne 'device' }).Count -gt 0) {
            Write-Host 'Sur le telephone : cocher "Toujours autoriser" puis Autoriser le debogage USB...' -ForegroundColor Cyan
            for ($i = 0; $i -lt 60 -and @($phones.Values | Where-Object { $_ -ne 'device' }).Count -gt 0; $i++) {
                Start-Sleep 1
                $phones = Get-Phones
            }
        }
        $ready = @($phones.Keys | Where-Object { $phones[$_] -eq 'device' })
        if ($ready.Count -eq 0) {
            Write-Host "Debogage USB pas autorise sur le telephone : appli Android non installee. Lien : $apkUrl" -ForegroundColor Yellow
        } else {
            $apkAsset = @($rel.assets | Where-Object name -eq 'Snoophone-android.apk')[0]
            $apk = Join-Path $env:TEMP 'Snoophone-android.apk'
            Write-Host 'Appli Android : telechargement...' -ForegroundColor Cyan
            Get-File $apkAsset.browser_download_url $apk $apkAsset.url
            if ("$($apkAsset.digest)" -match '^sha256:([0-9a-f]{64})$' -and (Get-FileHash $apk -Algorithm SHA256).Hash -ne $Matches[1]) {
                Remove-Item $apk -Force
                throw 'APK abime pendant le telechargement (empreinte differente).'
            }
            foreach ($serial in $ready) {
                $model = (& $adb -s $serial shell getprop ro.product.model 2>$null | Out-String).Trim()
                Write-Host "Installation sur $model..." -ForegroundColor Cyan
                $out = (& $adb -s $serial install -r $apk 2>&1 | Out-String).Trim()
                if ($out -match 'Success') {
                    Write-Host "Snoophone installe sur $model. Ouvre-le sur le telephone." -ForegroundColor Green
                } else {
                    Write-Host "Echec sur ${model} : $out" -ForegroundColor Yellow
                }
            }
            Remove-Item $apk -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $serverWasUp) { & $adb kill-server 2>$null | Out-Null }
} catch {
    Write-Host "Appli Android non installee ($($_.Exception.Message)). Lien : $apkUrl" -ForegroundColor Yellow
}
