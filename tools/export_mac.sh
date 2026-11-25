#!/usr/bin/env bash
set -e

# ==============================================================================
# Script d'export de Galsen-Life pour macOS
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="$PROJECT_DIR/export/macos"
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

echo "🚀 Export macOS de Galsen-Life avec $GODOT_BIN..."
echo "📂 Dossier de sortie : $EXPORT_DIR"

# Export debug macOS (DMG ou ZIP)
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --export-debug "macOS" "$EXPORT_DIR/galsen-life.dmg"

echo "✅ Export macOS terminé dans $EXPORT_DIR/galsen-life.dmg"
