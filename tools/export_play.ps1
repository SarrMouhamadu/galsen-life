# Galsen-Life : produit l'AAB signé pour Google Play (export/galsen-life.aab).
# Le mot de passe de la clé est demandé ici et passé à Godot par variable d'environnement
# (uniquement pour ce processus) : il n'est jamais écrit dans le projet ni sur le disque.
# Usage : powershell -ExecutionPolicy Bypass -File tools\export_play.ps1

$ErrorActionPreference = "Stop"
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) {
	Write-Host "Lance ce script dans un PowerShell normal (pas « en tant qu'administrateur ») : Godot n'y trouve pas le SDK Android." -ForegroundColor Yellow
	exit 1
}
$project = Split-Path -Parent $PSScriptRoot
$godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
$keystore = "$env:USERPROFILE\galsen-upload.keystore"
$aab = Join-Path $project "export\galsen-life.aab"

$sdk = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
Write-Host ("Diagnostic : utilisateur={0} SDK build-tools={1} réglages Godot={2}" -f $env:USERNAME, (Test-Path "$sdk\build-tools"), (Test-Path "$env:APPDATA\Godot\editor_settings-4.7.tres"))
if (-not (Test-Path $keystore)) { Write-Host "Clé introuvable : $keystore" -ForegroundColor Red; exit 1 }

$secure = Read-Host "Mot de passe de la clé galsen-upload" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))

$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $keystore
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "galsen"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $plain

if (Test-Path $aab) { Remove-Item $aab }
Write-Host "Construction de l'AAB signé (plusieurs minutes)..." -ForegroundColor Cyan
$p = Start-Process -FilePath $godot -ArgumentList "--headless", "--path", "`"$project`"", "--export-release", "`"Google Play`"", "`"$aab`"" -PassThru -NoNewWindow

# Godot reste parfois bloqué après Gradle : on attend que l'AAB soit écrit puis stable
$last = -1
while (-not $p.HasExited) {
	Start-Sleep -Seconds 5
	if (Test-Path $aab) {
		$size = (Get-Item $aab).Length
		if ($size -gt 0 -and $size -eq $last) { break }
		$last = $size
	}
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = ""
$plain = $null

$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
& "$project\android\build\gradlew.bat" -p "$project\android\build" --stop | Out-Null

if (Test-Path $aab) {
	Write-Host ("AAB prêt : {0} ({1:N0} Mo)" -f $aab, ((Get-Item $aab).Length / 1MB)) -ForegroundColor Green
	Write-Host "Envoie ce fichier dans la Play Console (Tests > Test interne > Créer une version)."
} else {
	Write-Host "Échec : aucun AAB produit. Vérifie le mot de passe." -ForegroundColor Red
	exit 1
}
