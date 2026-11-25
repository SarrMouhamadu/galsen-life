# Galsen-Life : construit un AAB de débogage (clé de débogage de Godot, sans mot de passe) pour vérifier
# que la compilation Gradle passe (modules Android comme AdMob) avant de signer la vraie version.
# Usage : powershell -ExecutionPolicy Bypass -File tools\export_check.ps1

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
$aab = Join-Path $project "export\verif-debug.aab"
$log = Join-Path $project "export\verif-debug.log"

$sdk = "$env:LOCALAPPDATA\Android\Sdk"
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"

if (Test-Path $aab) { Remove-Item $aab }
Write-Host "Construction de l'AAB de vérification (plusieurs minutes)..." -ForegroundColor Cyan
$p = Start-Process -FilePath $godot -ArgumentList "--headless", "--path", "`"$project`"", "--export-debug", "`"Google Play`"", "`"$aab`"" -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"

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
& "$project\android\build\gradlew.bat" -p "$project\android\build" --stop | Out-Null

if (Test-Path $aab) {
	Write-Host ("VERIF OK : {0} ({1:N0} Mo)" -f $aab, ((Get-Item $aab).Length / 1MB)) -ForegroundColor Green
} else {
	Write-Host "VERIF ECHEC : voir $log" -ForegroundColor Red
}
