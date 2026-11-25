#!/usr/bin/env bash
set -e

# ==============================================================================
# Diagnostic de l'environnement de développement Apple (macOS & iOS)
# ==============================================================================

echo "=== Diagnostic Environnement Apple pour Galsen-Life ==="
echo ""

# 1. Vérification de macOS
OS_VER=$(sw_vers -productVersion 2>/dev/null || echo "Inconnu")
ARCH=$(uname -m)
echo "💻 Système : macOS $OS_VER ($ARCH)"

# 2. Vérification de Xcode
if command -v xcodebuild >/dev/null 2>&1; then
    XCODE_VER=$(xcodebuild -version | tr '\n' ' ')
    echo "🛠️  Xcode : $XCODE_VER"
    XCODE_PATH=$(xcode-select -p)
    echo "    Chemin Developer : $XCODE_PATH"
else
    echo "❌ Xcode n'est pas détecté. Installez Xcode depuis le Mac App Store."
fi

# 3. Vérification des SDKs iOS & macOS
if command -v xcrun >/dev/null 2>&1; then
    IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo "Non trouvé")
    MAC_SDK=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo "Non trouvé")
    echo "📱 SDK iOS : $IOS_SDK"
    echo "🖥️  SDK macOS : $MAC_SDK"
fi

# 4. Vérification de Homebrew
if command -v brew >/dev/null 2>&1; then
    echo "🍺 Homebrew : Installé ($(brew --version | head -n 1))"
else
    echo "⚠️  Homebrew n'est pas installé."
fi

# 5. Détection de Godot
GODOT_BIN=""
if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="godot"
elif [ -f "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
elif [ -f "$HOME/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT_BIN="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
fi

if [ -n "$GODOT_BIN" ]; then
    G_VER=$("$GODOT_BIN" --version 2>/dev/null || echo "OK")
    echo "🤖 Godot Engine : Détecté ($GODOT_BIN - $G_VER)"
else
    echo "⚠️  Godot Engine non trouvé dans PATH ou /Applications."
    echo "   Pour l'installer via Homebrew : brew install --cask godot"
    echo "   Ou téléchargez Godot 4.7 depuis https://godotengine.org"
fi

# 6. Modèles d'export Godot
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates"
if [ -d "$TEMPLATES_DIR" ]; then
    echo "📦 Modèles d'export trouvés dans : $TEMPLATES_DIR"
    ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/    - /'
else
    echo "⚠️  Dossier de modèles d'export non encore créé ($TEMPLATES_DIR)"
    echo "   (Installez les modèles d'export 4.7 depuis l'éditeur : Projet -> Gérer les modèles d'exportation)"
fi

# 7. Identités de signature Apple (Code Signing)
echo ""
echo "🔑 Identités de signature de code (Keychain) :"
security find-identity -p codesigning -v 2>/dev/null || echo "    Aucune identité trouvée."

echo ""
echo "=== Fin du diagnostic ==="
