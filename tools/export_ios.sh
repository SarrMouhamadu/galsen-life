#!/usr/bin/env bash
set -e

# ==============================================================================
# Script d'export de Galsen-Life pour iOS (Projet Xcode)
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="$PROJECT_DIR/export/ios"
mkdir -p "$EXPORT_DIR"

# Détection de Godot
GODOT_BIN=""
if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="godot"
elif [ -f "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
elif [ -f "$HOME/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT_BIN="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
else
    echo "❌ Godot Engine n'a pas été trouvé."
    echo "Installez-le avec : brew install --cask godot"
    echo "ou placez Godot.app dans /Applications."
    exit 1
fi

echo "📱 Export iOS de Galsen-Life vers projet Xcode..."
echo "📂 Dossier de sortie : $EXPORT_DIR"

# Export projet Xcode iOS
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-debug "iOS" "$EXPORT_DIR/galsen-life.ipa"

# Nettoyage automatique du warning #pragma once dans dummy.h généré par Godot
DUMMY_H="$EXPORT_DIR/galsen-life/dummy.h"
if [ -f "$DUMMY_H" ] && grep -q "#pragma once" "$DUMMY_H"; then
    sed -i '' 's/#pragma once/#ifndef DUMMY_H\
#define DUMMY_H\
\
#endif \/\/ DUMMY_H/' "$DUMMY_H"
fi

# Correction automatique de la signature et compatibilité iOS étendue dans project.pbxproj
PBXPROJ="$EXPORT_DIR/galsen-life.xcodeproj/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
    sed -i '' 's/CODE_SIGN_IDENTITY = "Apple Distribution";/CODE_SIGN_IDENTITY = "Apple Development";/g' "$PBXPROJ"
    sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g' "$PBXPROJ"
    sed -i '' 's/TARGETED_DEVICE_FAMILY = "[0-9,]*";/TARGETED_DEVICE_FAMILY = "1,2";/g' "$PBXPROJ"
fi

# Activation de l'autorisation Game Center (com.apple.developer.game-center)
ENTITLEMENTS="$EXPORT_DIR/galsen-life/galsen-life.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.game-center bool true" "$ENTITLEMENTS" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :com.apple.developer.game-center true" "$ENTITLEMENTS" 2>/dev/null || true
fi

echo "✅ Export iOS terminé dans $EXPORT_DIR"
if [ -d "$EXPORT_DIR/galsen-life.xcodeproj" ]; then
    echo "👉 Pour ouvrir le projet dans Xcode :"
    echo "   open $EXPORT_DIR/galsen-life.xcodeproj"
fi
