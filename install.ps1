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
# D'abord la page GitHub Pages (latest.json + fichiers, publies par publish-pages.sh) : l'API des
# releases de GitHub renvoie parfois 504 pendant des heures. L'API reste le secours.
$pages = 'https://snoog43.github.io/snoophone-releases'
$info = $null
try { $info = Invoke-RestMethod "$pages/latest.json?t=$([DateTime]::UtcNow.Ticks)" -UseBasicParsing -ErrorAction Stop } catch {}
$rel = $null
if ($info -and $info.setup_sha256) {
    $tag = $info.tag
    $setupUrl = "$pages/Snoophone-x64-setup.exe"; $setupApi = $null; $setupHash = $info.setup_sha256
} else {
    $rel = $null
    for ($try = 1; -not $rel; $try++) {
        try { $rel = Invoke-RestMethod 'https://api.github.com/repos/Snoog43/snoophone-releases/releases/latest' -UseBasicParsing -ErrorAction Stop }
        catch { if ($try -ge 4) { throw }; Start-Sleep -Seconds (2 * $try) }
    }
    $asset = @($rel.assets | Where-Object name -eq 'Snoophone-x64-setup.exe')[0]
    if (-not $asset) { throw 'Snoophone-x64-setup.exe introuvable dans la derniere version.' }
    $tag = $rel.tag_name
    $setupUrl = $asset.browser_download_url; $setupApi = $asset.url
    $setupHash = if ("$($asset.digest)" -match '^sha256:([0-9a-f]{64})$') { $Matches[1] } else { $null }
}
$file = Join-Path $env:TEMP 'Snoophone-x64-setup.exe'
Write-Host "Snoophone $tag : telechargement..." -ForegroundColor Cyan
Get-File $setupUrl $file $setupApi
if ($setupHash -and (Get-FileHash $file -Algorithm SHA256).Hash -ne $setupHash) {
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
    # Accorde a Snoophone tout ce qu'il demande, sans rien toucher sur le telephone : autorisations
    # ordinaires (appels, SMS, contacts, photos, camera, micro...), acces speciaux (tous les fichiers,
    # parametres systeme, superposition, utilisation), notifications, Ne pas deranger,
    # accessibilite (controle depuis le PC) et batterie sans restriction.
    function Grant-All($serial) {
        $pkg = 'app.snoophone'
        $inRequested = $false
        foreach ($line in (& $adb -s $serial shell dumpsys package $pkg 2>$null)) {
            if ($line -match '^\s*requested permissions:\s*$') { $inRequested = $true; continue }
            if (-not $inRequested) { continue }
            if ($line -match ':\s*$') { break }
            if ($line -match '^\s*(android\.permission\.[A-Z_]+)\s*$' -and $Matches[1] -ne 'android.permission.ACCESS_BACKGROUND_LOCATION') {
                & $adb -s $serial shell pm grant $pkg $Matches[1] 2>$null | Out-Null
            }
        }
        foreach ($op in 'ACCESS_RESTRICTED_SETTINGS','MANAGE_EXTERNAL_STORAGE','WRITE_SETTINGS','SYSTEM_ALERT_WINDOW','GET_USAGE_STATS','REQUEST_INSTALL_PACKAGES','PROJECT_MEDIA','RUN_IN_BACKGROUND','RUN_ANY_IN_BACKGROUND') {
            & $adb -s $serial shell appops set $pkg $op allow 2>$null | Out-Null
        }
        & $adb -s $serial shell cmd notification allow_listener "$pkg/app.snoophone.android.notifications.NotificationListener" 2>$null | Out-Null
        & $adb -s $serial shell cmd notification allow_dnd $pkg 2>$null | Out-Null
        & $adb -s $serial shell dumpsys deviceidle whitelist "+$pkg" 2>$null | Out-Null
        $svc = "$pkg/app.snoophone.android.mirror.InputService"
        $cur = (& $adb -s $serial shell settings get secure enabled_accessibility_services 2>$null | Out-String).Trim()
        if ($cur -notlike "*$svc*") {
            $new = if ($cur -and $cur -ne 'null') { "${cur}:$svc" } else { $svc }
            & $adb -s $serial shell settings put secure enabled_accessibility_services "'$new'" 2>$null | Out-Null
            & $adb -s $serial shell settings put secure accessibility_enabled 1 2>$null | Out-Null
        }
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
            $apk = Join-Path $env:TEMP 'Snoophone-android.apk'
            Write-Host 'Appli Android : telechargement...' -ForegroundColor Cyan
            if ($rel) {
                $apkAsset = @($rel.assets | Where-Object name -eq 'Snoophone-android.apk')[0]
                Get-File $apkAsset.browser_download_url $apk $apkAsset.url
                $apkHash = if ("$($apkAsset.digest)" -match '^sha256:([0-9a-f]{64})$') { $Matches[1] } else { $null }
            } else {
                Get-File $apkUrl $apk
                $apkHash = $info.apk_sha256
            }
            if ($apkHash -and (Get-FileHash $apk -Algorithm SHA256).Hash -ne $apkHash) {
                Remove-Item $apk -Force
                throw 'APK abime pendant le telechargement (empreinte differente).'
            }
            foreach ($serial in $ready) {
                $model = (& $adb -s $serial shell getprop ro.product.model 2>$null | Out-String).Trim()
                Write-Host "Installation sur $model..." -ForegroundColor Cyan
                $out = (& $adb -s $serial install -r $apk 2>&1 | Out-String).Trim()
                if ($out -match 'Success') {
                    Write-Host "Snoophone installe sur $model. Autorisations..." -ForegroundColor Cyan
                    Grant-All $serial
                    Write-Host "Snoophone installe et tout autorise sur $model. Ouvre-le sur le telephone." -ForegroundColor Green
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
