#!/usr/bin/env bash
set -e

# ==============================================================================
# Script d'Archivage Release iOS & Préparation TestFlight / App Store
# Galsen-Life — Team ID: ZGS6PT6427 | Bundle ID: com.mouhamadousarr.galsenlife
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORT_DIR="$PROJECT_DIR/export/ios"
XCODE_PROJ="$EXPORT_DIR/galsen-life.xcodeproj"
ARCHIVE_PATH="$EXPORT_DIR/galsen-life.xcarchive"
SCHEME="galsen-life"
TEAM_ID="ZGS6PT6427"
BUNDLE_ID="com.mouhamadousarr.galsenlife"

echo "=================================================================="
echo "📦 Archivage iOS Release — Préparation TestFlight & App Store"
echo "=================================================================="
echo "🏢 Developer Team : $TEAM_ID"
echo "🆔 Bundle ID      : $BUNDLE_ID"
echo "📂 Projet Xcode   : $XCODE_PROJ"
echo "📁 Archive Cible  : $ARCHIVE_PATH"
echo ""

# 1. Vérification des prérequis
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "❌ Erreur : xcodebuild n'est pas disponible. Installez Xcode depuis le Mac App Store."
    exit 1
fi

if [ ! -d "$XCODE_PROJ" ]; then
    echo "⚙️  Génération initiale du projet Xcode via export Godot..."
    "$PROJECT_DIR/tools/export_ios.sh"
fi

# Nettoyage de l'ancienne archive
if [ -d "$ARCHIVE_PATH" ]; then
    echo "🧹 Suppression de l'ancienne archive : $ARCHIVE_PATH"
    rm -rf "$ARCHIVE_PATH"
fi

echo ""
echo "🚀 Lancement de la compilation Release et création du .xcarchive..."
echo "------------------------------------------------------------------"

xcodebuild -project "$XCODE_PROJ" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    archive

echo ""
echo "=================================================================="
echo "🎉 ARCHIVE CRÉÉE AVEC SUCCÈS !"
echo "=================================================================="
echo "📍 Chemin de l'archive : $ARCHIVE_PATH"
echo ""
echo "📱 Pour publier sur TestFlight ou l'App Store :"
echo "1. Double-cliquez sur l'archive pour l'ouvrir dans Xcode Organizer :"
echo "   open \"$ARCHIVE_PATH\""
echo "2. Cliquez sur 'Distribute App'"
echo "3. Choisissez 'TestFlight & App Store'"
echo "4. Xcode signera automatiquement avec votre compte Apple Developer ($TEAM_ID) et l'enverra sur App Store Connect !"
echo "=================================================================="
