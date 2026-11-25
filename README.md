# Galsen-Life 🇸🇳

**GTA RP version sénégalaise.** Vis ta vie dans le **vrai centre de Dakar** en 3D (Plateau et Médina, d'après OpenStreetMap) : conduis un taxi jaune et noir, livre le thiéboudienne de Chez Adja en Jakarta, vends du café Touba au marché Sandaga, mange un dibi... et gagne tes FCFA.

> Version 0.3 : prototype solo jouable. La ville suit le vrai plan de Dakar ; les personnages et véhicules sont faits de formes simples générées par le code, et pourront être remplacés par de vrais modèles 3D.

## Lancer le jeu

1. Installer **Godot 4.7** (version standard, pas .NET) :
   - Sur **macOS** : `brew install --cask godot`
   - Sur **Windows** : `winget install GodotEngine.GodotEngine`
2. Ouvrir Godot → **Importer** → choisir `project.godot` dans ce dossier.
3. Appuyer sur **F5**.

## Commandes

| Action | PC (AZERTY ou QWERTY) | Mobile | Manette |
|---|---|---|---|
| Bouger / conduire | ZQSD, WASD ou flèches | Joystick à gauche | Stick gauche |
| Caméra | Souris (clic pour la capturer) | Glisser à droite de l'écran | — |
| Action : monter/descendre, parler, travailler | E | ACTION | Y |
| Sauter / freiner | Espace | SAUT / FREIN | A |
| Courir | Maj | COURIR (ou joystick à fond) | B |
| Carte et GPS | M | CARTE | Back |
| Voler un véhicule | G | VOLER | X |
| Klaxon | H | KLAXON (en voiture) | LB |
| Radio on/off | R | — | RB |
| Pause | Échap | Bouton II | Start |
| Afficher les commandes tactiles sur PC | F1 | — | — |

## Contenu

**La ville** : environ 3,3 km × 3,3 km du vrai Dakar, de la Médina et Gueule Tapée au Plateau, au port et à l'Anse Bernard : vraies rues (228 noms : Avenue Pompidou, Blaise Diagne, Cheikh Anta Diop...), vrais bâtiments là où OpenStreetMap les connaît, sens uniques, côte et quais. Le Plateau étant peu cartographié, les îlots vides sont complétés par des immeubles générés, alignés sur les vraies rues.

**Quartiers** (affichés en haut à droite) : Dakar-Plateau, Médina, Rebeuss, Gibraltar, Gueule Tapée, Fass Delorme.

**Lieux réels** : Place de l'Indépendance, Marché Sandaga, Grande Mosquée (et son minaret), Hôpital Principal, Cathédrale du Souvenir africain, Assemblée nationale, Gare de Dakar, Marché Kermel, Marché Tilène, Gare routière Petersen, Porte du Troisième Millénaire, Commissariat de Rebeuss, Dibiterie Le Mboté. **Lieux du jeu** placés à côté : Café Touba (Sandaga), Chez Adja (Tilène), Garage Taxi (Petersen).

**Logement** (appli **Keur** du téléphone, « maison » en wolof) :

- **Chambre à la Médina** à louer (1 000 FCFA par jour, caution de 3 jours ; loyer prélevé chaque matin à 8 h, sur l'argent liquide puis sur le compte ; 3 jours d'impayés et le bailleur reprend la chambre).
- À acheter (+5 % de frais de notaire, paiement en liquide complété par la banque) : **studio à Gueule Tapée** (250 000), **appartement au Plateau** (900 000, 1 place de garage), **villa au Cap Manuel** (4 500 000 : piscine, coffre-fort, garage de 3 voitures).
- Devant la porte : panneau « À LOUER / À VENDRE », visite, location ou achat. Intérieurs meublés selon le standing (natte et ventilateur, télévision et cuisine, salon, piscine).
- **Lit** : dormir jusqu'au matin ou faire une sieste (le temps avance, santé à 100, sauvegarde) — en ligne, l'heure de la ville est commune : on se repose seulement.
- On **se réveille chez soi** quand il n'y a pas de position sauvegardée. **Coffre-fort** de la villa pour mettre l'argent à l'abri.
- **Garage** : s'arrêter en voiture devant la porte pour la ranger (elle devient à toi : la reprendre n'est plus un vol), la ressortir depuis le menu de la porte.

**Emploi réaliste — chaque travail a son patron** :

- Pour travailler, il faut **être embauché** : on va parler au patron sur place (ou on le trouve avec l'appli **Liggéey** du téléphone, « travail » en wolof : offres, conditions, horaires, GPS).
- **Conditions** : expérience (services faits ailleurs), **permis de conduire** pour la camionnette Jumbo et le taxi, pas d'embauche quand la police te recherche.
- **Entretien** : une question du métier (rendre la monnaie, commission de 1 %, arnaque au code secret, code de la route...). Mauvaise réponse : « Reviens quand tu seras prêt ».
- **Contrat** : horaires d'ouverture, **paie remise par le patron en fin de service**, réputation, **promotion** (chef, +25 %) après 5 bons services, **renvoi** si l'on abandonne son poste ou si la police s'en mêle (réembauche après 3 services ailleurs).
- Patrons : Adja Diallo (livraison de thiéb), Serigne Mbaye (café Touba), Modou Ndiaye (**apprenti de car rapide** : à chaque arrêt, crier la destination pour faire monter les passagers, 30 % de la recette), Fatou Sow (Orange Money), Ousmane Ba (Wave), Mme Ndiaye (caisse Jadida), Moussa Fall (dépôt Jumbo), Pape Diop (**taxi au versement** : il confie son taxi, on garde les courses et on lui verse 5 000 FCFA à la fin).
- **Auto-école Teranga** (M. Sarr, près de la gare) : examen du code de la route, 3 questions, 15 000 FCFA → permis de conduire.

**Véhicules** : taxi jaune à hayon (damier noir, enseigne TAXI), autocar orange, car interurbain blanc (garés à la gare routière Petersen et dans la circulation), car rapide (« Alhamdoulilah »), Jakarta (moto), clando, voiture de police. Les autocars évitent les ruelles trop étroites. Le trafic roule à droite ; tu peux voler une voiture en marche.

**Métiers**
- **Taximan** : monte dans un taxi, suis la balise jaune, prends le client et dépose-le (balise verte). Le prix dépend de la distance.
- **Livreur** : à Chez Adja, prends une commande et livre-la avant que le plat refroidisse (« Dafa sedd ! »). Pourboire si tu es rapide.
- **Vendeur de café Touba** : reste à ton stand au marché Sandaga, 150 FCFA la tasse.

**Routes** : trottoirs surélevés avec bordures, lignes centrales et de rive, **passages piétons** et **feux tricolores** aux vrais emplacements (OpenStreetMap). Les voitures s'arrêtent au rouge ; griller un feu devant la police donne une étoile. Panneaux STOP, limitations à 50 et plaques de rue.

**Maisons** : murs patinés, toits-terrasses avec murets, portes métalliques colorées, boutiques avec rideau de fer et enseigne peinte sur les grands axes, balcons, réservoirs d'eau, fers à béton en attente.

**Lieux réels ajoutés** : plage de l'Anse Bernard (sable, palmiers, parasols, pirogues), 31 terrains de sport (foot, basket, tennis, dont le Stade Iba Mar Diop), parcs, 37 lieux de culte (mosquées de quartier avec minaret, églises dont Saint-Laurent de Gibraltar et la Cathédrale).

**Marchés** (Sandaga, Tilène, Kermel) : étals de fruits et légumes, poisson, pain et beignets, tissus wax et bazin, jus locaux, artisanat, avec des vendeurs. [E] pour acheter ou marchander ; la nourriture se mange, le reste va dans le sac (visible dans le menu pause).

**Entreprises** (noms sur les enseignes, sans logos) :
- **Orange Money** et **Wave** : kiosques d'agent, [E] pour servir les clients (dépôts et retraits), 1 % de commission.
- **Jadida** : caissier au supermarché, 250 FCFA par client.
- **Jumbo** : tournée de livraison de cartons dans 3 boutiques avec la camionnette Jumbo, plus une prime.

**Carte et GPS** : touche M (ou bouton CARTE) pour la carte complète. Zoom à la molette ou avec +/−, glisser pour se déplacer, clic pour poser un point GPS : l'itinéraire s'affiche en violet sur la mini-carte.

**Véhicules** : vrais modèles 3D (packs « Realistic Car Pack » et « LowPoly Public Transport » de Quaternius, licence CC0), convertis par `tools/convert_vehicles.py` (Blender) dans `vehicles/`. Taxi jaune de Dakar, clandos (berlines de couleurs variées), police bleu nuit et blanc avec gyrophare rouge et bleu, jeep militaire (SUV kaki), camionnette Jumbo, car rapide jaune et bleu, autocar orange et car interurbain blanc. Les roues tournent, les phares brillent, la carrosserie a des reflets (profils Moyen et Élevé).

**Graphismes et ville vivante** :

- **Trois profils graphiques** (menu Pause → « Graphismes ») : *Faible* (téléphones modestes : rendu à 70 %, sans ombres, distance 240 m), *Moyen* (85 %, ombres proches, anticrénelage 2x, flaques, 4 lumières de lampadaires) et *Élevé* (100 %, ombres jusqu'à 90 m, anticrénelage 4x, 8 lumières). Par défaut : Moyen sur téléphone, Élevé sur PC. Test : `-- --graphics=faible`.
- **Météo** synchronisée en ligne : ciel dégagé, nuageux, harmattan (brume ocre), pluie d'hivernage (gouttes, routes mouillées et brillantes, flaques qui reflètent le ciel, bruit de pluie) et orage (éclairs, tonnerre). Test : `-- --weather=pluie`.
- **Nuit** : 3 000 lampadaires le long des rues (halo orangé au sol, vraies lumières autour du joueur), fenêtres allumées dans les immeubles.
- **Quartiers** : Plateau d'affaires (tours vitrées, boutiques), quartiers populaires de la Médina, Gueule Tapée, Fass et Rebeuss (maisons basses, toits en tôle, réservoirs), villas de luxe du Cap Manuel (façades blanches, baies vitrées, pergolas, palmiers), zones industrielles du port (entrepôts, portes roulantes).
- **Vrais lieux OpenStreetMap** : stations-service (Shell, Total, Oilibya, Star Oil, Puma...), banques (SGBS, BHS, BNDE, BGFI, Orabank, Coris Bank), hôpitaux et cliniques, commissariats, 70 restaurants, garages, supermarchés, parkings avec voitures garées, voie ferrée, **ponts** (tablier, parapets, piliers, rampes) et **tunnel de Soumbédioune** sous la Corniche. Tous sont dans le GPS du téléphone.
- **Intérieurs visitables** (action devant la porte) : banque (compte en banque : déposer et retirer, l'argent du compte est à l'abri), restaurant (thiéboudienne, yassa, mafé...), boutique de station, hôpital (soins), commissariat (payer son amende), supermarché. **Garage** : s'arrêter devant en voiture pour la repeindre (5 000 FCFA, une étoile de moins).
- **Végétation** : 1 000 arbres d'alignement sur les boulevards, 430 palmiers sur la Corniche et dans les villas.
- **Reflets** sur les carrosseries et les vitres (Moyen et Élevé), **sons spatialisés** (vagues, foule des marchés, moteurs des voitures proches), **niveaux de détail** (passants et voitures lointains masqués, modèles simplifiés au loin).
- Mesure : `-- --fps-test` (images par seconde moyennes).

**Personnages réalistes** : peau avec shader dédié (`characters/skin/skin.gdshader` : relief des pores et rides, brillance variable, diffusion de la lumière sous la peau, contre-jour), textures de peau 2048 px, yeux détaillés, cheveux crépus mats, tissus mats et bazin brillant pour le grand boubou. Éclairage ambiant venu du ciel et rendu des couleurs AgX. Gros plan pour vérifier : `godot --path . -- --portrait --hour=16 --cam-dist=0.75` (option `--models=heros,homme_tunique,...`).

**Téléphone** : touche C (ou bouton TÉL). Applications : **Messages** (SMS aux autres joueurs en ligne, et aux contacts Maman, Tonton Ablaye et Fatou qui répondent), **Wave** et **Orange Money** (virements aux joueurs en ligne, frais 1 %, historique des opérations reçues et envoyées), **GPS** (les 30 lieux les plus proches, un toucher pour y aller), **Services** (appeler un taxi ou la police, son métier), **Joueurs** (qui est en ligne, son métier, sa distance, avec SMS / Wave / GPS) et **Carte**. Le bouton TÉL affiche le nombre de SMS non lus.

**Transports en commun (comme passager, en payant)**
- **Bus** : 2 lignes avec abribus (carrés orange et bleus sur la mini-carte). Ligne 1 : Place de l'Indépendance, Sandaga, Petersen, Tilène, Grande Mosquée. Ligne 2 : Gare de Dakar, Kermel, Hôpital Principal, Assemblée nationale, Cathédrale, Porte du Millénaire. À l'arrêt : [E] pour attendre, le bus s'arrête, tu montes (200 FCFA) ; [E] pendant le trajet pour descendre au prochain arrêt.
- **Car rapide** : [E] près d'un car rapide qui passe, 150 FCFA ; [E] pour « Descente ! ».
- **Taxi** : [E] près d'un taxi qui passe, tu choisis ta destination (prix selon la distance, environ 400 FCFA/km) et le taxi t'y conduit.
- Pour **voler** un véhicule au lieu de payer : [G] (bouton VOLER sur mobile).

**L'armée** : à partir de 4 étoiles, des jeeps militaires et des soldats à pied rejoignent la police (encore plus à 5 étoiles). Un soldat qui te rattrape à pied t'arrête. La **caserne** (État-major de la Gendarmerie) est une zone militaire gardée : y entrer donne 2 étoiles. Personne ne tire.

**Survie RP** : la satiété baisse avec le temps. Mange un dibi (1 500 FCFA) ; si tu t'évanouis, tu te réveilles à l'Hôpital Principal (3 000 FCFA de soins).

**Police (étoiles de recherche)**
- Délits : voler une voiture en marche (+1), renverser un passant (+1), percuter la police (+1), voler une voiture de police (+2). Maximum 5 étoiles.
- Chaque étoile ajoute une voiture à la poursuite ; les renforts arrivent par les rues, sirène et gyrophare allumés.
- Pour **semer** la police : reste 12 s hors de vue (à plus de 70 m, ou caché derrière les bâtiments) pour perdre une étoile.
- Rester arrêté 2 s près d'une voiture de police = **arrestation** : 1 000 FCFA d'amende par étoile, et tu ressors du Commissariat Central.

**Mini-carte** : en haut à droite, orientée nord. Balise d'objectif en jaune (collée au bord si elle est loin), police en rouge/bleu, lieux importants en couleur.

**Son** (entièrement synthétisé par le code) : moteur dont le régime suit la vitesse, klaxon, sirènes 3D, pièces quand tu gagnes de l'argent, et **Radio Galsen FM** qui joue une boucle de mbalax (sabar, basse, balafon) dans les taxis, cars rapides et clandos.

**Ambiance** : cycle jour/nuit (une journée = 24 min), brume d'harmattan, passants qui parlent wolof (« Nanga def ? », « Jërëjëf ! »).

**Sauvegarde** : automatique toutes les 30 s et en quittant (argent, position, heure, statistiques).

## Mode en ligne

Au lancement, le menu propose **Jouer en solo** ou **Jouer en ligne** (adresse du serveur, pseudo, mot de passe, choix du personnage, « Créer un compte » la première fois). En ligne : on voit les autres joueurs (personnage animé et pseudo, ou leur véhicule), **chat** avec T ou le bouton CHAT, heure de la ville partagée, et la partie (argent, position, sac) est **sauvegardée sur le serveur**.

Monde partagé : le **trafic** est simulé par le serveur (mêmes voitures, mêmes feux pour tous) ; on peut voler ou héler une de ces voitures, elle quitte alors le trafic commun. Un joueur **recherché** apparaît en rouge (« RECHERCHÉ ** ») et on voit les voitures de police qui le poursuivent. Près d'un autre joueur, la touche d'action ouvre un menu : **monter dans sa voiture** comme passager (action pour descendre) ou **lui donner de l'argent** (500 à 10 000 FCFA).

Jouer ensemble :

- **Chat de proximité** : par défaut, le message n'est lu que par les joueurs à moins de 40 m et s'affiche en bulle au-dessus de la tête ; « /t message » pour tout Dakar, « /g message » pour son groupe.
- **Chat vocal** : maintenir **V** (ou le bouton MICRO) pour parler aux joueurs à moins de 35 m — leur voix vient de leur personnage (son 3D), « ((( parle ))) » s'affiche sous leur pseudo ; maintenir **B** (ou RADIO) pour la radio du groupe, entendue par tous les membres même de loin. Voix compressée (μ-law 8 kHz, ~8 Ko/s pendant qu'on parle), relayée par le serveur seulement aux joueurs concernés. Pause → « Chat vocal : activé/coupé ». Sur Android, le jeu demande l'accès au micro.
- **Groupes (appli Mbokk)** : créer sa « famille », inviter les joueurs proches ; le nom du groupe s'affiche sous le pseudo, les membres apparaissent sur la mini-carte même de loin (GPS vers eux).
- **Courses de voitures (appli Défis)** : au volant, ouvrir une course vers un lieu (mise 0, 1 000 ou 5 000 FCFA) ; les joueurs à moins de 400 m sont prévenus et s'inscrivent sur la ligne de départ ; compte à rebours, points de passage calculés sur le vrai réseau routier, classement ; la cagnotte va au vainqueur.
- **Duels de lutte (mbapatt)** : près d'un joueur, action → « Défier à la lutte » (avec ou sans mise) ; manches à choix simultanés (charger bat crocheter, crocheter bat esquiver, esquiver bat charger) ; le premier à 3 points gagne les deux mises.

Métiers RP entre joueurs (bouton **MÉTIERS**, en haut à droite) :

- **Taximan** : au volant d'un taxi, on est en service. Les joueurs appellent un taxi depuis MÉTIERS (leur position s'affiche sur le GPS du chauffeur), montent, choisissent la destination et paient la course à l'arrivée.
- **Policier** : prendre le service au **Commissariat** (une voiture de patrouille est fournie, on peut la conduire sans être recherché). Le joueur recherché le plus proche apparaît sur le GPS ; on l'arrête à pied (action près de lui). Prime : 1 000 FCFA par étoile, l'arrêté paie l'amende.
- **Vendeur** : tenir un étal à Sandaga, Tilène ou Kermel. Les passants achètent régulièrement, et les autres joueurs peuvent acheter (action près du vendeur).
- **Salaire** versé par le serveur toutes les 2 minutes de service : policier 1 500, taximan 500, vendeur 500 FCFA.
- Le pseudo des joueurs affiche leur métier (« Policier », « Taximan », « Vendeur »).

Le serveur est le jeu lui-même lancé sans écran (`-- --server`, port UDP 7777). Installation sur un VPS : voir [server/README.md](server/README.md).

Test local : `godot --headless --path . -- --server --bind=127.0.0.1`, puis dans le jeu, adresse `127.0.0.1`.

## Arène nationale de lutte (Pikine)

L'Arène nationale est à une douzaine de kilomètres du Plateau, hors de la carte : c'est une zone à part. On y va en **car depuis la gare routière Petersen** (300 FCFA, marqueur jaune) ou en **taxi** (destination « Arène nationale (Pikine) », 4 500 FCFA) ; même chose pour revenir. Sur place : billet au guichet (2 000 FCFA), **combats** de lutte (bàkk au son du sabar, corps à corps, chute), **paris** (1 000 FCFA, gain doublé) et **combat du joueur** : appuyer sur ACTION quand le curseur est dans la zone verte, 3 prises pour gagner 25 000 FCFA. Les lutteurs ont des noms inventés.

## Animations

Les personnages bougent avec de vraies animations en **capture de mouvement** (Universal Animation Library de Quaternius, **CC0**) : attente, marche, jogging, sprint, parler, danse, conduite, chute… Elles sont adaptées à chaque personnage par `tools/bake_animations.gd` (`characters/anims/*.res`) ; l'allure suit la vitesse (marche normale à 2 m/s, course à 6,5 m/s avec Maj).

```bash
godot --headless --path . -s res://tools/bake_animations.gd
```

## Personnages réalistes

Les 9 personnages (`characters/realistic/*.glb` : le héros, 4 hommes, 4 femmes) sont générés avec **Blender** et **MPFB** (MakeHuman pour Blender), uniquement à partir des ressources **CC0** de MakeHuman : peaux africaines, cheveux, polo, robes, jupe imprimée, tunique, etc. Ils ont un vrai squelette de jeu vidéo ; la marche est animée par le code (`scripts/util/real_character.gd`) et les tenues des passants sont teintées au hasard.

Pour les régénérer ou en ajouter (modifier la liste `CHARACTERS` du script) :

```bash
blender --background --python tools/make_characters.py -- characters/realistic --preview
```

Pré-requis : Blender 4.2+ avec l'extension MPFB, et les bibliothèques CC0 de MakeHuman installées dans MPFB (makehuman_system_assets, skins01, skins02, hair01, shirts01, pants01, shoes01, dress01, skirts01, hats01 : https://static.makehumancommunity.org/assets/assetpacks.html).

## Régénérer la ville depuis OpenStreetMap

La ville est pré-calculée dans `world/dakar/` (maillages fusionnés par blocs de 400 m, réseau routier, mini-carte). Pour la mettre à jour avec des données OSM plus récentes ou changer la zone :

1. Relancer la requête `tools/osm/query.overpassql` sur https://overpass-turbo.eu (ou l'API Overpass) et enregistrer le résultat dans `tools/osm/dakar_raw.json`.
2. Lancer la conversion (quelques secondes) :

```bash
godot --headless --path . -s res://tools/bake_dakar.gd
```

Pour une autre zone, changer `BBOX` (et `LAT0`/`LON0`) dans `tools/bake_dakar.gd` et dans la requête.

**Données** : © les contributeurs d'OpenStreetMap, sous licence ODbL (https://www.openstreetmap.org/copyright). La mention est affichée dans le jeu (écran titre et pause).

## Structure

```
scenes/main.tscn              scène principale (construit tout au démarrage)
scripts/main.gd               assemblage, trafic, piétons, jour/nuit
scripts/autoload/game_state.gd argent, santé, étoiles, heure, sauvegarde, touches
scripts/autoload/audio.gd     sons et radio mbalax synthétisés
scripts/world/dakar_city.gd   chargement du vrai Dakar, réseau routier, adresses, itinéraires
tools/bake_dakar.gd           conversion OpenStreetMap → ville 3D (outil hors-jeu)
world/dakar/                  ville pré-calculée (city.scn, data.json, minimap.png)
scripts/player/player.gd      personnage, entrée/sortie des véhicules
scripts/vehicles/vehicle.gd   conduite arcade et IA du trafic
scripts/npc/pedestrian.gd     piétons
scripts/jobs/job_manager.gd   métiers, balise d'objectif
scripts/police/police_manager.gd poursuites, renforts, arrestation
scripts/ui/minimap.gd         mini-carte
scripts/ui/hud.gd             interface, pause, écran titre
scripts/ui/touch_controls.gd  commandes tactiles multi-doigts
scripts/util/mk.gd            fabrique de formes et de personnages
tests/smoke_test.gd           test automatique des métiers
```

## Tests

```bash
godot --headless --path . -s res://tests/smoke_test.gd
```

Options utiles pour vérifier le rendu : `-- --map` (carte et GPS), `-- "--look=Wave"` (face à un lieu), `-- "--overhead=Terrain de foot"` (vue aérienne), `-- --portrait` (personnages de face), `-- --portrait --walk` (marche), `-- --showcase` (les nouveaux véhicules côte à côte), `-- "--at=Gare routière Petersen"` (démarrer devant un lieu), `godot --path . -- --hour=21 --test-taxi --screenshot=capture.png`, ou `-- --wanted=3 --delay=9 --screenshot=poursuite.png` pour une poursuite.

## Essayer sur Android

Sur ce PC, tout est déjà installé et configuré : Java 17, SDK Android, modèles d'export Godot 4.7.2, clé de test.

**1. Fabriquer l'APK** (à refaire après chaque modification du jeu) :
- dans Godot : *Projet → Exporter… → Android → Exporter le projet*, puis enregistrer dans `export/galsen-life.apk` ;
- ou en ligne de commande :

```bash
godot --headless --path . --export-debug "Android" export/galsen-life.apk
```

**2. Mettre le fichier sur le téléphone** : copie `export/galsen-life.apk` par câble USB (dossier *Téléchargements* du téléphone), Google Drive, ou WhatsApp en te l'envoyant à toi-même.

**3. L'installer** : sur le téléphone, ouvre le fichier depuis l'application *Fichiers* (ou depuis Drive/WhatsApp). Android demande d'**autoriser l'installation d'applications inconnues** pour cette application : accepte, puis touche **Installer**. Si Play Protect affiche un avertissement, choisis *Installer quand même* : c'est normal pour une app qui ne vient pas du Play Store.

**Pour mettre à jour** : refais l'APK et réinstalle-le par-dessus, la sauvegarde est conservée.

L'APK est une version de **test** (signée avec la clé debug standard d'Android). Pour le Play Store, il faudra une clé de publication et un export AAB.

Le projet utilise le rendu **Compatibility** (OpenGL ES 3), qui tourne aussi sur les téléphones Android d'entrée de gamme. L'écran est en paysage.

## Essayer sur Mac et iOS

Consultez le guide complet dans [docs/apple-deploy.md](docs/apple-deploy.md).

- **Vérifier l'environnement Mac** :
  ```bash
  ./tools/check_apple_env.sh
  ```
- **Exporter pour macOS (.dmg)** :
  ```bash
  ./tools/export_mac.sh
  ```
- **Exporter pour iOS (Projet Xcode)** :
  ```bash
  ./tools/export_ios.sh
  open export/ios/galsen-life.xcodeproj
  ```
  *(Ouvre le projet dans Xcode pour le signer avec votre compte développeur et le lancer sur iPhone/iPad).*

## Prochaines étapes

- GPS avec itinéraire sur la mini-carte, grande carte dans le menu pause
- Plusieurs stations de radio, vraie musique sénégalaise (avec les droits)
- Vrais modèles 3D (Blender → glTF) pour les personnages et les véhicules
- Logement, garde-robe (boubous, maillots des Lions), achat de véhicules
- Lutte sénégalaise à l'arène, événements (Tabaski, Magal)
- **Mode RP en ligne** : serveur multijoueur (Godot High-Level Multiplayer ou Nakama), comptes joueurs, économie partagée
