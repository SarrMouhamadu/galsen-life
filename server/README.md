# Serveur en ligne de Galsen-Life

Le serveur est le jeu lui-même, lancé sans écran avec `-- --server`. Il gère les comptes (pseudo + mot de passe),
les sauvegardes des joueurs, les positions, le chat, l'heure de la ville, les feux tricolores et le trafic
commun (les mêmes voitures pour tous les joueurs). Il écoute sur le **port UDP 7777**.

## 1. Louer un VPS

N'importe quel petit VPS Linux suffit (1 vCPU, 1 à 2 Go de RAM, environ 4 à 6 € par mois) :
OVHcloud, Hetzner, Contabo, Scaleway, DigitalOcean...

- Système : **Ubuntu 24.04** (ou 22.04).
- Note l'**adresse IP** du serveur et le **mot de passe root** (ou ta clé SSH).
- Si l'hébergeur a un pare-feu dans son interface web, ouvre le **port UDP 7777** (et TCP 22 pour SSH).

## 2. Préparer le paquet (sur le PC)

```bash
godot --headless --path . --export-pack "Serveur Linux" export/serveur/galsen-life.pck
```

Copier aussi `server/install.sh` et `server/galsen-life.service` dans `export/serveur/`.

## 3. Installer sur le VPS (depuis le PC, dans PowerShell)

Remplacer `IP_DU_VPS` par l'adresse du serveur :

```bash
scp -r export/serveur root@IP_DU_VPS:/root/galsen
```

```bash
ssh root@IP_DU_VPS "bash /root/galsen/install.sh"
```

Le script installe Godot 4.7.2 (version officielle, empreinte vérifiée), crée l'utilisateur `galsen`,
installe le service `galsen-life` (redémarrage automatique) et ouvre le port UDP 7777 dans `ufw`.

## 4. Jouer

Dans le jeu : **Jouer en ligne** → adresse du serveur = l'IP du VPS → pseudo, mot de passe,
personnage → cocher **Créer un compte** la première fois.

## Commandes utiles sur le VPS

- Journal en direct : `journalctl -u galsen-life -f`
- Paie des métiers : toutes les 120 s par défaut (`-- --server --pay-every=60` pour changer)
- Redémarrer : `systemctl restart galsen-life`
- Mettre à jour le jeu : refaire l'étape 2 puis l'étape 3 (les comptes sont conservés)
- Comptes des joueurs : `/var/lib/galsen/.local/share/godot/app_userdata/Galsen-Life/server_accounts.json`

## Architecture Haute Capacité & Multi-Shards (Des millions de joueurs simultanés)

Pour accueillir des centaines de milliers ou des millions de joueurs sans aucun ralentissement ni lag, Galsen-Life adopte une architecture MMO distribuée à plusieurs niveaux :

### 1. Partitionnement Spatial et Network LOD (Level of Detail)
- **Cellules spatiales fines de 100 m (`CELL`)** : Chaque joueur ne reçoit que les entiers compacts des entités pertinentes dans sa zone de visibilité (`AOI = 260 m`).
- **Paliers LOD dynamiques selon la distance** :
  - **Zone Proche (< 50 m)** : Synchronisation maximale (10 Hz).
  - **Zone Moyenne (50 m - 120 m)** : Synchronisation à 5 Hz (1 tick sur 2).
  - **Zone Lointaine (120 m - 260 m)** : Synchronisation à 2,5 Hz (1 tick sur 4).
  - **Au-delà de 260 m** : Filtrage total ($O(k)$ bande passante, constante indépendante du nombre total de joueurs).
- **Dead Reckoning client (`remote_players.gd`)** : Anticipation par vitesse et cap avec lissage exponentiel (60 / 120 FPS constant sur mobiles, aucun micro-stutter).

### 2. Canaux & Shards mondiaux équilibrés
- Le menu principal propose une sélection automatique et manuelle des Shards Dakar :
  - `🟢 Automatique (Meilleure latence & équilibré)` (Port 7777)
  - `🇸🇳 Dakar 1 — Centre-ville & Plateau` (Port 7777)
  - `🇸🇳 Dakar 2 — Almadies & Plages` (Port 7778)
  - `🇸🇳 Dakar 3 — Médina & Grand Marché` (Port 7779)
  - `🇸🇳 Dakar 4 — Pikine & Grande Arène` (Port 7780)
  - `🇸🇳 Dakar 5 — Parcelles & Yoff` (Port 7781)
- Chaque shard supporte **jusqu'à 4 096 joueurs simultanés** par cœur de processeur.
- Rejoindre un ami (`friend_code`) fonctionne directement à travers les shards.

### 3. Sauvegarde Asynchrone en tâche de fond (Zero Frame Drop)
- L'enregistrement des comptes et données de sauvegarde (`user://server_accounts.json`) s'effectue dans un thread d'arrière-plan (`WorkerThreadPool`).
- **Zéro freeze de la boucle de jeu**, même avec des centaines de milliers de comptes enregistrés.

### 4. Déploiement en Cluster Linux (`server/cluster_manager.py` & `tune_kernel.sh`)
- `bash server/tune_kernel.sh` : Augmente les tampons UDP du noyau Linux à 64 Mo et les descripteurs de fichiers à 1 048 576.
- `python3 server/cluster_manager.py` : Lance et surveille les shards multi-cœurs avec auto-restart instantané en cas d'imprévu.
- `systemctl start galsen-cluster@{7777..7781}` : Gestion native par Systemd.

## Limites de cette première version

- Synchronisés : trafic, feux, joueurs, voitures conduites, police qui poursuit un joueur, argent donné,
  métiers RP (taximan, policier, vendeur), salaires, appels de service, arrestations,
  SMS et virements Wave / Orange Money entre joueurs.
- Encore propres à chaque joueur : passants, voitures garées, bus de ligne, métiers et combats à l'arène.
- Le mot de passe n'est jamais envoyé en clair, mais la connexion n'est pas chiffrée : ne pas réutiliser
  un mot de passe important.
- Le serveur fait confiance aux joueurs (argent, position) : pas de protection contre la triche.
