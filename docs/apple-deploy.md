# Déploiement Apple (macOS & iOS) — Galsen-Life 🇸🇳

Ce guide détaille les étapes pour exporter, compiler et exécuter **Galsen-Life** sur **macOS** (Mac Apple Silicon / Intel) et sur **iOS** (iPhone et iPad).

---

## 1. Prérequis sur votre Mac

1. **Xcode** (déjà installé sur votre Mac avec les outils en ligne de commande).
2. **Identité de développeur Apple** (votre certificat `Apple Development: Mouhamadou SARR (FS2VCF5D79)` est déjà configuré dans le Trousseau d'accès).
3. **Godot Engine 4.7** :
   ```bash
   brew install --cask godot
   ```
   *Ou téléchargez directement Godot 4.7 (version standard) depuis [godotengine.org](https://godotengine.org).*
4. **Modèles d'exportation Godot** :
   - Ouvrez Godot.
   - Allez dans le menu : **Éditeur → Gérer les modèles d'exportation**.
   - Cliquez sur **Télécharger et installer** (version 4.7).

Pour vérifier la configuration complète à tout moment :
```bash
./tools/check_apple_env.sh
```

---

## 2. Exporter et jouer sur macOS

### Méthode 1 : Lancement direct en développement
Dans le dossier du projet :
```bash
godot --path .
```
Ou ouvrez Godot, importez `project.godot` et appuyez sur **F5**.

### Méthode 2 : Exporter l'application macOS autonome (.dmg / .app)
Exécutez le script d'automatisation :
```bash
./tools/export_mac.sh
```
Ou depuis Godot :
- **Projet → Exporter…**
- Choisissez le préréglage **macOS**.
- Cliquez sur **Exporter le projet** et enregistrez dans `export/macos/galsen-life.dmg`.

---

## 3. Exporter et jouer sur iOS (iPhone / iPad)

### Étape 1 : Générer le projet Xcode
Exécutez le script d'exportation :
```bash
./tools/export_ios.sh
```
*Ou dans Godot : **Projet → Exporter… → iOS → Exporter le projet** vers `export/ios/galsen-life.ipa`.*

Godot va générer un projet Xcode complet dans `export/ios/`.

### Étape 2 : Ouvrir et signer dans Xcode
Ouvrez le projet généré dans Xcode :
```bash
open export/ios/galsen-life.xcodeproj
```

Dans Xcode :
1. Dans le navigateur de gauche, cliquez sur le projet racine **galsen-life**.
2. Allez dans l'onglet **Signing & Capabilities** de la cible principale.
3. Cochez **Automatically manage signing**.
4. Sélectionnez votre équipe de développement : **Mouhamadou SARR (FS2VCF5D79)**.
5. Vérifiez le Bundle Identifier : `com.galsenliferp.game`.

### Étape 3 : Lancer sur votre iPhone / iPad ou Simulateur
- Connectez votre iPhone ou iPad en USB à votre Mac (ou choisissez un simulateur iPhone/iPad dans le menu en haut).
- Sur votre appareil physique, assurez-vous d'avoir activé le **Mode Développeur** (*Réglages → Confidentialité et sécurité → Mode Développeur*).
- Cliquez sur le bouton **Play (Run)** dans Xcode (ou `Cmd + R`).
- L'application compile, s'installe et se lance en plein écran avec les contrôles tactiles virtuels sénégalais !

---

## 4. Spécificités & Adaptations iOS / macOS

* **Microphone pour le chat vocal de proximité** :
  L'autorisation `NSMicrophoneUsageDescription` est configurée dans le préréglage iOS (*« Galsen-Life utilise le microphone pour le chat vocal de proximité et la radio en jeu »*). iOS affiche automatiquement la boîte de dialogue système lors du premier appui sur le bouton micro.
* **Contrôles tactiles vs Clavier/Souris** :
  - Sur **iOS** : L'interface tactile multi-doigts (`touch_controls.gd`) avec stick directionnel et boutons contextuels (Action, Voler, Klaxon, Tél, etc.) s'active automatiquement.
  - Sur **macOS** : Le jeu utilise le clavier physique (ZQSD/WASD), la souris (clic capturé) ou les manettes connectées en Bluetooth/USB. La touche **F1** permet de tester l'interface tactile sur Mac si besoin.
* **Graphismes Apple Silicon** :
  Le profil graphique s'adapte automatiquement :
  - Sur **Mac** : Profil **Élevé** par défaut (ombres portées complètes, anti-aliasing, reflets sur les carrosseries).
  - Sur **iOS** : Profil **Moyen** dès 4 Go de mémoire unifiée (puces Apple A13 Bionic et ultérieures), sans surchauffe ni fuite mémoire.
* **Textures optimisées** :
  - iOS utilise la compression matérielle **ASTC**.
  - macOS utilise la compression matérielle **S3TC/BPTC**.

---

## 5. Publication sur l'App Store / TestFlight

Pour soumettre l'application sur **TestFlight** ou l'**App Store** :
1. Dans Xcode, sélectionnez la destination **Any iOS Device (arm64)**.
2. Allez dans le menu **Product → Archive**.
3. Une fois l'archive créée, cliquez sur **Distribute App → App Store Connect**.
4. Suivez les étapes de signature et d'envoi.
5. Retrouvez votre build sur [appstoreconnect.apple.com](https://appstoreconnect.apple.com) pour configurer les tests TestFlight ou la fiche App Store.
