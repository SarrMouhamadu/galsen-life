# Publication sur Google Play

## Fiche du Play Store (à copier dans la Play Console)

**Nom de l'application** (30 caractères max.) : `Galsen-Life : Dakar RP`

**Description courte** (80 max.) :
> Vis ta vie à Dakar : taxi, livraison, lutte, marchés et jeu en ligne entre amis.

**Description complète** :
> Galsen-Life est un jeu de rôle en monde ouvert qui se déroule dans le vrai Dakar : le Plateau, la Médina, Sandaga, Kermel, la Corniche…
>
> 🚕 **Travaille** : taximan, livreur, vendeur de café Touba, apprenti car rapide, agent Orange Money ou Wave… Chaque métier a son patron qui te recrute après un entretien.
> 🏠 **Installe-toi** : loue une chambre, achète une maison, gare tes voitures.
> 🛍️ **Vis la ville** : marchés animés, dibiteries, stations-service, banques, hôpital, commissariat.
> 🤼 **Lutte sénégalaise** : défie les autres joueurs dans l'arène ou dans la rue.
> 🌐 **En ligne** : retrouve tes amis sur le serveur, forme un groupe (Mbokk), organise des courses, parle-leur au micro.
> ☀️🌧️ **Ville vivante** : jour et nuit, harmattan, pluie d'hivernage, circulation, passants.
>
> Téranga ! Le jeu évolue régulièrement avec de nouvelles activités.

**Catégorie** : Jeux › Simulation (ou Rôle)
**Coordonnées** : une adresse e-mail de contact (obligatoire, affichée publiquement)
**Politique de confidentialité** : URL publique de `docs/confidentialite.html` (voir plus bas)

## Images à fournir
- Icône 512 × 512 PNG
- Image de présentation 1024 × 500
- Au moins 2 captures d'écran de téléphone (16:9, 1080 px de haut minimum conseillé)

## Formulaires de la Play Console
- **Sécurité des données** : données collectées = pseudo (identifiant de compte), mot de passe (sous forme d'empreinte), progression de jeu, audio (chat vocal, transmis en direct, non stocké), messages dans l'appli (chat, non archivés). Pas de partage avec des tiers. Données chiffrées en transit : **non** (ENet ne chiffre pas), réponds honnêtement. Suppression du compte possible : **oui** (dans l'appli + par e-mail).
- **Suppression de compte** : Google demande aussi un lien web. On peut utiliser la section 6 de la politique de confidentialité.
- **Classification du contenu (IARC)** : violence légère (lutte, police), interaction entre utilisateurs (chat texte et vocal), pas d'achats intégrés.
- **Public cible** : 13 ans et plus.
- **Publicités** : non.

## Étapes
1. Créer un compte développeur Google Play (25 $ une fois) : https://play.google.com/console/signup
   Les nouveaux comptes personnels doivent faire un **test fermé avec au moins 12 testeurs pendant 14 jours** avant de pouvoir publier en production.
2. Créer la clé d'envoi (une seule fois, à garder précieusement avec son mot de passe) — voir la commande `keytool` ci-dessous.
3. Exporter l'AAB signé avec le préréglage « Google Play ».
4. Dans la Play Console : créer l'application, remplir la fiche et les formulaires, envoyer l'AAB en **Test interne**, puis **Test fermé**, puis **Production**.

### Créer la clé d'envoi
```
keytool -genkeypair -v -keystore C:\Users\<toi>\galsen-upload.keystore -alias galsen -keyalg RSA -keysize 2048 -validity 10000
```
Ne la mets jamais dans le dépôt git (`*.keystore` est ignoré). Si tu la perds, Google peut la réinitialiser (Play App Signing), mais c'est long.

### Exporter l'AAB signé
Les identifiants de la clé sont lus dans des variables d'environnement (jamais écrits dans le projet) :
```
set GODOT_ANDROID_KEYSTORE_RELEASE_PATH=C:\Users\<toi>\galsen-upload.keystore
set GODOT_ANDROID_KEYSTORE_RELEASE_USER=galsen
set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=<ton mot de passe>
godot --headless --path . --export-release "Google Play" export/galsen-life.aab
```

### À chaque mise à jour
Augmenter `version/code` (et `version/name`) dans le préréglage « Google Play » de `export_presets.cfg`, puis réexporter.
Si le réseau change, mettre à jour le serveur **avant** de publier (les joueurs doivent avoir la même version que le serveur).
