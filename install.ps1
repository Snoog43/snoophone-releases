# Snoophone : irm https://raw.githubusercontent.com/Snoog43/snoophone-releases/main/install.ps1 | iex
# Telecharge le dernier Snoophone-x64-setup.exe des releases de github.com/Snoog43/snoophone-releases, verifie son empreinte SHA256
# (publiee par GitHub) puis l'ouvre. Deja installe : l'installeur met a jour et relance Snoophone.
# Fichier en ASCII sans BOM : il est lu par irm puis execute par iex.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$rel = Invoke-RestMethod 'https://api.github.com/repos/Snoog43/snoophone-releases/releases/latest' -UseBasicParsing
$asset = @($rel.assets | Where-Object name -eq 'Snoophone-x64-setup.exe')[0]
if (-not $asset) { throw 'Snoophone-x64-setup.exe introuvable dans la derniere version.' }
$file = Join-Path $env:TEMP 'Snoophone-x64-setup.exe'
Write-Host "Snoophone $($rel.tag_name) : telechargement..." -ForegroundColor Cyan
Invoke-WebRequest $asset.browser_download_url -OutFile $file -UseBasicParsing
if ("$($asset.digest)" -match '^sha256:([0-9a-f]{64})$' -and (Get-FileHash $file -Algorithm SHA256).Hash -ne $Matches[1]) {
    Remove-Item $file -Force
    throw 'Fichier abime pendant le telechargement (empreinte differente) : relancer la commande.'
}
Write-Host 'Ouverture de l''installeur : accepter la demande administrateur.' -ForegroundColor Cyan
Start-Process $file
