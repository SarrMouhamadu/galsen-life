# Diagnostic : outils Android visibles par un PowerShell normal (hors de l'application Claude)
$pkg = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache"
$paths = [ordered]@{
	"SDK réel" = "$env:LOCALAPPDATA\Android\Sdk\build-tools"
	"SDK isolé" = "$pkg\Local\Android\Sdk\build-tools"
	"Modèles Godot réels" = "$env:APPDATA\Godot\export_templates\4.7.2.stable\android_source.zip"
	"Modèles Godot isolés" = "$pkg\Roaming\Godot\export_templates\4.7.2.stable\android_source.zip"
	"Clé debug réelle" = "$env:APPDATA\Godot\keystores\debug.keystore"
	"JDK 17" = "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot\bin\java.exe"
	"Godot" = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
}
foreach ($k in $paths.Keys) { Write-Host ("{0,-22} {1}  {2}" -f $k, (Test-Path $paths[$k]), $paths[$k]) }
Write-Host "--- réglages Android de l'éditeur Godot (réels) ---"
Select-String -Path "$env:APPDATA\Godot\editor_settings-4.7.tres" -Pattern "export/android" | ForEach-Object { $_.Line }
