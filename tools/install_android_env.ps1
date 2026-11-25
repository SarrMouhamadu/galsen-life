# Copie le SDK Android et les modèles d'export Godot depuis le dossier isolé de l'application Claude
# vers les emplacements Windows normaux (pour exporter depuis un PowerShell ordinaire).
$pkg = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache"
robocopy "$pkg\Local\Android\Sdk" "$env:LOCALAPPDATA\Android\Sdk" /E /NFL /NDL /NJH /NP /R:1 /W:1
robocopy "$pkg\Roaming\Godot\export_templates" "$env:APPDATA\Godot\export_templates" /E /NFL /NDL /NJH /NP /R:1 /W:1
Write-Host ("SDK : {0}   Modèles : {1}" -f (Test-Path "$env:LOCALAPPDATA\Android\Sdk\build-tools"), (Test-Path "$env:APPDATA\Godot\export_templates\4.7.2.stable\android_source.zip"))
