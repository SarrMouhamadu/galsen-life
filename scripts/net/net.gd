extends Node
## Mode en ligne de Galsen-Life (Godot high-level multiplayer sur ENet, port UDP 7777).
##
## - Serveur : le même jeu lancé sans écran avec `-- --server` (sur un VPS Linux). Il gère les comptes,
##   les sauvegardes, la position des joueurs, le chat et l'heure de la ville.
## - Client : se connecte, s'identifie (pseudo + mot de passe), puis envoie son état 10 fois par seconde
##   et reçoit celui des autres joueurs.
##
## Mot de passe : jamais envoyé en clair. Le client n'envoie que SHA-256(pseudo + mot de passe), mélangé
## à un nombre aléatoire donné par le serveur pour la connexion. C'est une protection simple : ne pas
## réutiliser un mot de passe important.

signal connection_changed(status: String)
signal login_result(ok: bool, message: String)
signal chat_received(from: String, text: String)
signal bubble(sender: int, text: String) ## message de proximité : bulle au-dessus de la tête
signal voice_received(sender: int, data: PackedByteArray, channel: String) ## voix (μ-law 8 kHz)
signal traffic_received(cars) ## PackedInt32Array : 7 entiers par voiture
signal job_target(text: String, pos: Vector3) ## appel d'un client, suspect à arrêter...
signal arrested(cop: String)
signal sms_received(from: String, text: String)
signal money_received(from: String, amount: int, reason: String)
signal account_deleted ## le serveur a effacé le compte de ce joueur
signal friend_joined(ok: bool, message: String, friend_name: String, friend_pos: Vector3, friend_peer: int, code: String)

const PORT := 7777
## Serveur officiel du jeu (VPS Hetzner) : adresse proposée par défaut dans le menu
const DEFAULT_HOST := "188.245.233.220"
const DEFAULT_MAX_PLAYERS := 4095
var max_players := DEFAULT_MAX_PLAYERS
const SEND_RATE := 0.1
## Zone d'intérêt adaptative & Répartition par cellules spatiales
const AOI := 260.0
const AOI_MAX := 48
const CELL := 100.0
## Paliers de réseau LOD (Level of Detail) : économise 70% de bande passante dans les foules denses
const LOD_NEAR := 50.0   ## 10 Hz (tous les ticks)
const LOD_MID := 120.0   ## 5 Hz (1 tick sur 2)
const LOD_FAR := 260.0   ## 2.5 Hz (1 tick sur 4)

## Canaux / Shards de Dakar pour distribuer des millions de joueurs sans latence
const CHANNELS := [
	{"id": "auto", "name": "🟢 Automatique (Meilleure latence & équilibré)", "port": 7777, "host": DEFAULT_HOST},
	{"id": "dakar_1", "name": "🇸🇳 Dakar 1 — Centre-ville & Plateau", "port": 7777, "host": DEFAULT_HOST},
	{"id": "dakar_2", "name": "🇸🇳 Dakar 2 — Almadies & Plages", "port": 7778, "host": DEFAULT_HOST},
	{"id": "dakar_3", "name": "🇸🇳 Dakar 3 — Médina & Grand Marché", "port": 7779, "host": DEFAULT_HOST},
	{"id": "dakar_4", "name": "🇸🇳 Dakar 4 — Pikine & Grande Arène", "port": 7780, "host": DEFAULT_HOST},
	{"id": "dakar_5", "name": "🇸🇳 Dakar 5 — Parcelles & Yoff", "port": 7781, "host": DEFAULT_HOST},
]
var current_channel := "auto"
var _tick_frame := 0
var _saving_task := -1
var _peer_packets := {} ## id -> [count, window_start_msec]
## Véhicule conduit, envoyé sous forme d'indice
const VEH := ["", "taxi", "bus", "coach", "car_rapide", "jakarta", "clando", "police", "van", "army", "ndiaga", "grosse_moto", "charette", "brt", "suv"]
const STRIDE := 8 ## entiers par joueur dans un instantané
## Un client renvoie son état au moins toutes les HEARTBEAT secondes, même immobile
const HEARTBEAT := 1.0
const ACCOUNTS_PATH := "user://server_accounts.json"
const BLOCKED_PATH := "user://blocked_players.json"
const FRIENDS_PATH := "user://saved_friends.json"
const REPORTS_LOG := "user://reports_log.json"
var blocked_players := {} ## pseudo en minuscules → true
var saved_friends: Array = [] ## [{"pseudo": String, "code": String, "last_seen": int}]
var friend_code := ""
var pending_friend_join_code := ""
var _code_to_account := {} ## côté serveur : "GAL-12345" → pseudo
const ServerTraffic = preload("res://scripts/net/server_traffic.gd")
const Social = preload("res://scripts/net/social.gd")
const NetLutte = preload("res://scripts/net/net_lutte.gd")
const NetFight = preload("res://scripts/net/net_fight.gd")
const NetEmotes = preload("res://scripts/net/net_emotes.gd")
const NetFactions = preload("res://scripts/net/net_factions.gd")
const NetProperties = preload("res://scripts/net/net_properties.gd")
const NetTrade = preload("res://scripts/net/net_trade.gd")
const NetFoot = preload("res://scripts/net/net_foot.gd")
const NetCity = preload("res://scripts/net/net_city.gd")
const Factions = preload("res://scripts/net/factions.gd")
const LOCAL_CHAT := 40.0 ## portée du chat de proximité (mètres)
const VOICE_RANGE := 35.0 ## portée de la voix de proximité (mètres)
const VOICE_MAX_BYTES := 2400 ## un paquet de voix (≈0,3 s) au plus
## Métiers RP en ligne : salaire versé par le serveur à chaque paie (toutes les PAY_EVERY secondes)
const JOBS := {"taxi": "Taximan", "police": "Policier", "vendeur": "Vendeur", "samu": "SAMU", "gang": "Gang de la Médina", "mecanicien": "Mécanicien"}
const SALARY := {"taxi": 500, "vendeur": 500, "mecanicien": 500} ## factions (police, samu, gang) : Factions.salary, selon le grade
const PAY_EVERY := 120.0
const AVATARS := [
	"heros", "lutteur1", "footballeur1", "femme_robe", "homme_age", "soldat",
	"homme_ville", "footballeuse", "femme_maman", "homme_afro", "homme_tunique",
	"femme_jupe", "femme_ville", "lutteur2", "gardien", "jayden_carter"
]

var is_server := false
var online := false ## connecté ET identifié
var pseudo := ""
var avatar := "heros"
var remote := {} ## (client) joueurs PROCHES : id de pair → {pseudo, avatar, state}
var roster := {} ## (client) TOUS les joueurs connectés : id → {pseudo, avatar, job, wl}
var light := false ## (test de charge) bot : compte les instantanés sans les décoder
var received := 0 ## instantanés reçus (statistiques des bots)
var server_time := -1.0
# Horloge commune (secondes) : feux tricolores synchronisés
var _clock := 0.0
var _clock_base := 0.0
var _clock_at := 0
var _traffic = null

# Côté serveur
var _accounts := {} ## pseudo → {hash, avatar, save}
var _sessions := {} ## id de pair → pseudo
var _states := {} ## id de pair → état
var _nonces := {} ## id de pair → nombre aléatoire pour la connexion
var _dirty := false
var _save_t := 0.0
var _send_t := 0.0
var _time_t := 0.0
var _pending_login := {}
var fight ## bagarres de rue entre joueurs (nœud enfant « Bagarre »)
var emotes ## émotes vues par les joueurs proches (nœud enfant « Emotes »)
var factions ## grades, SAMU et joueurs à terre (nœud enfant « Factions »)
var properties ## propriétaires des maisons et commerces (nœud enfant « Proprietes »)
var foot ## matchs de mini-foot entre joueurs (nœud enfant « Foot »)
var trade ## échanges d'objets, d'argent et de véhicules entre joueurs (nœud enfant « Echanges »)
var city ## banque, mairie, mécanicien (nœud enfant « Ville »)
var lutte ## écuries et journées de lutte entre joueurs (nœud enfant « Lutte »)
var social ## groupes, courses, duels (nœud enfant « Social », même chemin sur le serveur et chez les joueurs)
var _grid := {} ## (serveur) cellule → identifiants des joueurs
var _enc := {} ## (serveur) id → joueur déjà encodé (PackedInt32Array)
var _cell_snap := {} ## (serveur) cellule → instantané partagé par tous les joueurs de la cellule
var _rings: Array = [] ## (serveur) décalages de cellules, du plus proche au plus loin
var _pos := {} ## (serveur) id → position
var _stats_t := 10.0
var _stats_us := 0
var _stats_max := 0
var _stats_frames := 0
var _last_sent: Array = []
var _last_sent_t := 0.0
var _pay_t := PAY_EVERY
var _traffic_t := 0.0
## (serveur) changements de la liste des joueurs, envoyés groupés une fois par seconde
var _delta_add := {} ## id → [pseudo, avatar]
var _delta_remove: Array = []
var _delta_job := {} ## id → [métier, étoiles]
var _delta_tenue := {} ## id → tenue (scripts/util/outfits.gd)
var _delta_t := 1.0
var _prof := {"trafic": 0, "joueurs": 0, "voitures": 0, "etats": 0, "connexions": 0, "sauvegarde": 0}
var _pay_every := PAY_EVERY


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	social = Social.new()
	social.name = "Social"
	social.net = self
	add_child(social)
	lutte = NetLutte.new()
	lutte.name = "Lutte"
	lutte.net = self
	add_child(lutte)
	fight = NetFight.new()
	fight.name = "Bagarre"
	fight.net = self
	add_child(fight)
	emotes = NetEmotes.new()
	emotes.name = "Emotes"
	emotes.net = self
	add_child(emotes)
	factions = NetFactions.new()
	factions.name = "Factions"
	factions.net = self
	add_child(factions)
	properties = NetProperties.new()
	properties.name = "Proprietes"
	properties.net = self
	add_child(properties)
	trade = NetTrade.new()
	trade.name = "Echanges"
	trade.net = self
	add_child(trade)
	foot = NetFoot.new()
	foot.name = "Foot"
	foot.net = self
	add_child(foot)
	city = NetCity.new()
	city.name = "Ville"
	city.net = self
	add_child(city)
	load_blocked_players()
	load_saved_friends()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Impossible de joindre le serveur."))
	multiplayer.server_disconnected.connect(func(): _fail("Le serveur a coupé la connexion."))
	if "--server" in OS.get_cmdline_user_args():
		start_server()


func _exit_tree() -> void:
	if is_server:
		if _saving_task != -1:
			WorkerThreadPool.wait_for_task_completion(_saving_task)
			_saving_task = -1
		if _dirty:
			var tmp_path := ACCOUNTS_PATH + ".tmp"
			var f := FileAccess.open(tmp_path, FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(_accounts))
				f.close()
				if FileAccess.file_exists(ACCOUNTS_PATH):
					DirAccess.copy_absolute(ACCOUNTS_PATH, ACCOUNTS_PATH + ".bak")
				DirAccess.rename_absolute(tmp_path, ACCOUNTS_PATH)


# --- Serveur -----------------------------------------------------------------------------

func start_server(port := PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	# Test local : -- --server --bind=127.0.0.1 (n'écoute que sur ce PC)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bind="):
			peer.set_bind_ip(a.trim_prefix("--bind="))
		elif a.begins_with("--port="):
			port = a.trim_prefix("--port=").to_int()
		elif a.begins_with("--max-players="):
			max_players = clampi(a.trim_prefix("--max-players=").to_int(), 1, 4095)
	max_players = clampi(max_players, 1, 4095)
	var err := peer.create_server(port, max_players)
	if err != OK:
		printerr("Serveur : impossible d'ouvrir le port %d (erreur %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	# Le serveur n'affiche rien : 60 calculs par seconde suffisent (et laissent le processeur respirer)
	Engine.max_fps = 60
	Engine.physics_ticks_per_second = 10
	_load_accounts()
	social.load_groups()
	lutte.load_ecuries()
	# Test : -- --server --pay-every=10 (paie plus fréquente)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pay-every="):
			_pay_every = maxf(5.0, a.trim_prefix("--pay-every=").to_float())
			_pay_t = _pay_every
	# Test de charge : -- --server --no-traffic (sans trafic partagé)
	if not "--no-traffic" in OS.get_cmdline_user_args():
		_traffic = ServerTraffic.new()
		add_child(_traffic)
	print("Serveur Galsen-Life Shard en écoute sur le port UDP %d (capacité %d joueurs, %d comptes)" % [port, max_players, _accounts.size()])
	# Le serveur n'a pas besoin de la ville : une scène vide suffit.
	get_tree().call_deferred("change_scene_to_file", "res://scenes/server.tscn")
	return OK


## Recherche insensible à la casse d'un compte (garantit qu'un joueur retrouvera toujours son compte
## même si la première lettre a été mise en majuscule par le clavier mobile ou s'il y a une divergence de casse).
func _get_account_key(who: String) -> String:
	var clean := who.strip_edges()
	if clean == "":
		return ""
	if _accounts.has(clean):
		return clean
	var lower := clean.to_lower()
	for k in _accounts:
		if str(k).strip_edges().to_lower() == lower:
			return str(k)
	return ""


func _load_accounts() -> void:
	if not FileAccess.file_exists(ACCOUNTS_PATH):
		if FileAccess.file_exists(ACCOUNTS_PATH + ".bak"):
			print("[SÉCURITÉ] Restauration automatique des comptes depuis le fichier de secours .bak")
			DirAccess.copy_absolute(ACCOUNTS_PATH + ".bak", ACCOUNTS_PATH)
		else:
			return
	var data = JSON.parse_string(FileAccess.get_file_as_string(ACCOUNTS_PATH))
	if data is Dictionary:
		_accounts = data
	elif FileAccess.file_exists(ACCOUNTS_PATH + ".bak"):
		print("[SÉCURITÉ] Fichier comptes corrompu, chargement du secours .bak")
		var bdata = JSON.parse_string(FileAccess.get_file_as_string(ACCOUNTS_PATH + ".bak"))
		if bdata is Dictionary:
			_accounts = bdata
	_code_to_account.clear()
	for who in _accounts:
		var acc = _accounts[who]
		if acc is Dictionary:
			if not acc.has("friend_code"):
				acc["friend_code"] = generate_friend_code(str(who))
				_dirty = true
			if not acc.has("display_name"):
				acc["display_name"] = str(who)
			_code_to_account[str(acc["friend_code"]).to_upper()] = str(who)


func _save_accounts(sync := false) -> void:
	if _saving_task != -1 and not WorkerThreadPool.is_task_completed(_saving_task):
		if sync:
			WorkerThreadPool.wait_for_task_completion(_saving_task)
			_saving_task = -1
		else:
			return # Écriture précédente encore en cours sur le disque, on évite d'empiler
	if _saving_task != -1:
		WorkerThreadPool.wait_for_task_completion(_saving_task)
		_saving_task = -1
	var accounts_copy: Dictionary = _accounts.duplicate(true)
	_dirty = false
	if sync:
		var json_str := JSON.stringify(accounts_copy)
		var tmp_path := ACCOUNTS_PATH + ".tmp"
		var f := FileAccess.open(tmp_path, FileAccess.WRITE)
		if f:
			f.store_string(json_str)
			f.close()
			if FileAccess.file_exists(ACCOUNTS_PATH):
				DirAccess.copy_absolute(ACCOUNTS_PATH, ACCOUNTS_PATH + ".bak")
			DirAccess.rename_absolute(tmp_path, ACCOUNTS_PATH)
	else:
		_saving_task = WorkerThreadPool.add_task(func():
			var json_str := JSON.stringify(accounts_copy)
			var tmp_path := ACCOUNTS_PATH + ".tmp"
			var f := FileAccess.open(tmp_path, FileAccess.WRITE)
			if f:
				f.store_string(json_str)
				f.close()
				if FileAccess.file_exists(ACCOUNTS_PATH):
					DirAccess.copy_absolute(ACCOUNTS_PATH, ACCOUNTS_PATH + ".bak")
				DirAccess.rename_absolute(tmp_path, ACCOUNTS_PATH)
		)


## Tolérance réseau : un joueur dont le jeu charge la ville (téléphone lent) ne répond plus pendant
## plusieurs secondes ; on attend jusqu'à 60 s avant de le considérer comme parti.
const TIMEOUT_MIN_MS := 30000
const TIMEOUT_MAX_MS := 60000


func _patient(peer_id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		var p := enet.get_peer(peer_id)
		if p:
			p.set_timeout(64, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


func _on_peer_connected(id: int) -> void:
	if not is_server:
		return
	_patient(id)
	var nonce := "%x%x" % [randi(), randi()]
	_nonces[id] = nonce
	rpc_challenge.rpc_id(id, nonce)


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	var who: String = _sessions.get(id, "")
	_sessions.erase(id)
	_states.erase(id)
	_pos.erase(id)
	_nonces.erase(id)
	_peer_packets.erase(id)
	social.on_leave(id, who)
	lutte.on_leave(id, who)
	if who != "":
		_delta_add.erase(id)
		_delta_job.erase(id)
		_delta_tenue.erase(id)
		_delta_remove.append(id)
		emotes.forget(id)
		factions.forget(id)
		properties.forget(id)
		trade.forget(id, who)
		foot.forget(id, who)
		city.forget(id)
		print("%s s'est déconnecté (%d en ligne)" % [who, _sessions.size()])
		if _sessions.size() <= 100:
			_broadcast_chat("Serveur", "%s a quitté Dakar." % who)


@rpc("authority", "reliable")
func rpc_challenge(nonce: String) -> void:
	if _pending_login.is_empty():
		return
	var key := _key_hash(_pending_login["pseudo"], _pending_login["password"])
	var proof := _sha(key + nonce)
	rpc_login.rpc_id(1, _pending_login["pseudo"], proof, key if _pending_login["create"] else "", _pending_login["avatar"])


@rpc("any_peer", "reliable")
func rpc_login(who: String, proof: String, new_key: String, wanted_avatar: String) -> void:
	if not is_server:
		return
	var t_login := Time.get_ticks_usec()
	_login(who, proof, new_key, wanted_avatar)
	_prof["connexions"] += Time.get_ticks_usec() - t_login


func _login(who: String, proof: String, new_key: String, wanted_avatar: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	who = who.strip_edges()
	if who.length() < 3 or who.length() > 16:
		rpc_login_result.rpc_id(id, false, "Le pseudo doit faire 3 à 16 caractères.", {}, "")
		return

	var acc_key := _get_account_key(who)
	var nonce: String = _nonces.get(id, "")

	if new_key != "":
		# Création d'un nouveau compte : vérification insensible à la casse
		if acc_key != "":
			rpc_login_result.rpc_id(id, false, "Ce pseudo est déjà pris.", {}, "")
			return
		var fcode := generate_friend_code(who)
		var tries := 0
		while _code_to_account.has(fcode) and tries < 100:
			fcode = "GAL-%05d" % ((absi(who.hash()) + tries + 1000) % 90000 + 10000)
			tries += 1
		_accounts[who] = {
			"hash": new_key,
			"avatar": wanted_avatar if wanted_avatar in AVATARS else "heros",
			"save": {},
			"friend_code": fcode,
			"display_name": who
		}
		_code_to_account[fcode] = who
		_dirty = true
		_save_accounts(true) # Sauvegarde immédiate et synchrone pour garantir 0 perte de compte
		acc_key = who
		print("Nouveau compte créé et sauvegardé avec succès : %s (code ami %s)" % [who, fcode])
	elif acc_key == "":
		rpc_login_result.rpc_id(id, false, "Compte inconnu. Coche « Créer un compte ».", {}, "")
		return

	var acc: Dictionary = _accounts[acc_key]
	var display_who: String = str(acc.get("display_name", acc_key))

	if not acc.has("friend_code"):
		acc["friend_code"] = generate_friend_code(display_who)
		_code_to_account[acc["friend_code"].to_upper()] = acc_key
		_dirty = true

	# Vérification du mot de passe
	if _sha(acc["hash"] + nonce) != proof:
		rpc_login_result.rpc_id(id, false, "Mot de passe incorrect.", {}, "")
		return

	# Si ce joueur avait une session précédente encore active sur le serveur (ex: appli fermée brutalement sur mobile)
	# On déconnecte l'ancien pair et on reprend la session instantanément sans bloquer le joueur !
	var old_peer_id := -1
	for sid in _sessions:
		if _sessions[sid].to_lower() == acc_key.to_lower():
			old_peer_id = sid
			break
	if old_peer_id != -1 and old_peer_id != id:
		print("[SESSION] Remplacement session zombie pour %s (peer %d remplacé par %d)" % [display_who, old_peer_id, id])
		_sessions.erase(old_peer_id)
		_states.erase(old_peer_id)
		_pos.erase(old_peer_id)
		_nonces.erase(old_peer_id)
		_peer_packets.erase(old_peer_id)
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.has_peer(old_peer_id):
			multiplayer.multiplayer_peer.disconnect_peer(old_peer_id)

	if wanted_avatar in AVATARS and wanted_avatar != acc.get("avatar", ""):
		acc["avatar"] = wanted_avatar
		_dirty = true

	_sessions[id] = display_who
	print("%s s'est connecté (%d en ligne)" % [display_who, _sessions.size()])
	rpc_login_result.rpc_id(id, true, "Bienvenue à Dakar, %s !" % display_who, acc.get("save", {}), acc.get("avatar", "heros"))

	var full := {}
	for other in _sessions:
		var st: Dictionary = _states.get(other, {})
		var o_key := _get_account_key(_sessions[other])
		var oacc: Dictionary = _accounts.get(o_key if o_key != "" else _sessions[other], {})
		full[other] = [_sessions[other], oacc.get("avatar", "heros"), st.get("job", ""), st.get("wl", 0), _tenue_of(oacc)]
	rpc_roster_full.rpc_id(id, full)
	_delta_add[id] = [display_who, acc.get("avatar", "heros"), _tenue_of(acc)]
	social.on_join(id, display_who)
	lutte.on_join(id, display_who)
	if _sessions.size() <= 100:
		_broadcast_chat("Serveur", "%s est arrivé à Dakar." % display_who)


## État compact : [x, y, z, cap, vitesse, véhicule, passager, étoiles, métier, policiers]
@rpc("any_peer", "unreliable_ordered")
func rpc_state(a: Array) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _sessions.has(id) or a.size() < 10:
		return
	# Protection anti-DoS et limitation de débit : max 30 paquets par seconde par pair
	var now := Time.get_ticks_msec()
	var rate: Array = _peer_packets.get(id, [0, now])
	if now - int(rate[1]) > 1000:
		rate[0] = 1
		rate[1] = now
		_peer_packets[id] = rate
	else:
		rate[0] = int(rate[0]) + 1
		if int(rate[0]) > 30:
			return # Débit excessif ignoré immédiatement sans charger le CPU
	var t_in := Time.get_ticks_usec()
	var old: Dictionary = _states.get(id, {})
	var st := {"x": float(a[0]), "y": float(a[1]), "z": float(a[2]), "r": float(a[3]), "sp": float(a[4]),
		"v": str(a[5]).left(16), "w": int(a[6]), "wl": clampi(int(a[7]), 0, 5), "job": str(a[8]).left(12), "pol": a[9] if a[9] is Array else []}
	_states[id] = st
	_pos[id] = Vector3(st["x"], st["y"], st["z"])
	# Métier ou étoiles changés : tout le monde le sait (liste des joueurs du téléphone, policiers...)
	if old.get("job", "") != st["job"] or int(old.get("wl", 0)) != st["wl"]:
		_delta_job[id] = [st["job"], st["wl"]]
		if st["job"] == "samu" and old.get("job", "") != "samu":
			factions.on_samu_duty(id)
	_prof["etats"] += Time.get_ticks_usec() - t_in


@rpc("any_peer", "reliable")
func rpc_save(save: Dictionary) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _sessions.has(id):
		return
	var who: String = _sessions[id]
	var acc_key := _get_account_key(who)
	if acc_key != "" and _accounts.has(acc_key):
		var acc: Dictionary = _accounts[acc_key]
		var old := _tenue_of(acc)
		# Sécurité serveur anti-triche : validation des sauts d'argent suspects
		var prev = acc.get("save", {})
		if prev is Dictionary and prev.has("money") and save.has("money"):
			var prev_tot := int(prev.get("money", 0)) + int(prev.get("bank", 0))
			var new_tot := int(save.get("money", 0)) + int(save.get("bank", 0))
			if new_tot > prev_tot + 150000:
				print("[SÉCURITÉ] Sauvegarde suspecte pour %s (+%d FCFA d'un coup) : montant plafonné" % [who, new_tot - prev_tot])
				save["money"] = int(prev.get("money", 0)) + 30000
		acc["save"] = save
		_dirty = true
		# Tenue changée (appli Sapé) : les autres joueurs la voient
		if _tenue_of(acc) != old:
			_delta_tenue[id] = _tenue_of(acc)


## Faction d'un joueur connecté, lue dans sa sauvegarde ("" s'il n'en a pas)
func _faction_of(id: int) -> String:
	var save = _accounts.get(_sessions.get(id, ""), {}).get("save", {})
	var fa = save.get("faction", {}) if save is Dictionary else {}
	var fid := str(fa.get("id", "")) if fa is Dictionary else ""
	return fid if Factions.FACTIONS.has(fid) else ""


## Expérience de faction d'un joueur, lue dans sa sauvegarde (0 s'il n'est pas de cette faction)
func faction_xp(id: int, job: String) -> int:
	var save = _accounts.get(_sessions.get(id, ""), {}).get("save", {})
	var fa = save.get("faction", {}) if save is Dictionary else {}
	if not fa is Dictionary or str(fa.get("id", "")) != job:
		return 0
	return clampi(int(fa.get("xp", 0)), 0, 100000)


## Tenue d'un compte, lue dans sa sauvegarde (texte court, vérifié à l'affichage)
static func _tenue_of(acc: Dictionary) -> String:
	var save = acc.get("save", {})
	return str(save.get("tenue", "")).left(64) if save is Dictionary else ""


## Suppression définitive du compte (exigence de Google Play) : pseudo, mot de passe, partie en ligne, groupe.
@rpc("any_peer", "reliable")
func rpc_delete_account() -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = _sessions.get(id, "")
	var acc_key := _get_account_key(who)
	if who == "" or acc_key == "":
		return
	social.forget(who)
	lutte.forget(who)
	properties.forget_account(who)
	city.forget_account(who)
	_accounts.erase(acc_key)
	_save_accounts(true)
	print("Compte supprimé définitivement à la demande du joueur : %s" % who)
	rpc_account_deleted.rpc_id(id)
	get_tree().create_timer(1.5).timeout.connect(func():
		if multiplayer.multiplayer_peer and _sessions.has(id):
			multiplayer.multiplayer_peer.disconnect_peer(id))


@rpc("authority", "reliable")
func rpc_account_deleted() -> void:
	account_deleted.emit()


func delete_account() -> void:
	if online:
		rpc_delete_account.rpc_id(1)


## Chat : canal « local » (bulle, joueurs à moins de LOCAL_CHAT m), « all » (tout Dakar), « group » (son groupe)
@rpc("any_peer", "reliable")
func rpc_chat(text: String, channel: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _sessions.has(id):
		return
	text = text.strip_edges().left(160)
	var who: String = _sessions[id]
	match channel:
		"all":
			_broadcast_chat("[Tous] " + who, text)
		"faction":
			var fid := _faction_of(id)
			if fid == "":
				rpc_notice.rpc_id(id, "Tu n'es dans aucune faction (menu MÉTIERS).")
				return
			var tag: String = Factions.FACTIONS[fid]["name"]
			for other in _sessions:
				if _faction_of(other) == fid:
					rpc_chat_msg.rpc_id(other, "[Radio %s] %s" % [tag, who], text)
		"group":
			var g: String = social.group_of(who)
			if g == "":
				rpc_notice.rpc_id(id, "Tu n'as pas de groupe (téléphone → Mbokk).")
				return
			for other in _sessions:
				if social.group_of(_sessions[other]) == g:
					rpc_chat_msg.rpc_id(other, "[%s] %s" % [g, who], text)
		_:
			var me: Vector3 = _pos.get(id, Vector3.ZERO)
			for other in _sessions:
				var p: Vector3 = _pos.get(other, Vector3(INF, 0, INF))
				if other == id or Vector2(p.x - me.x, p.z - me.z).length() < LOCAL_CHAT:
					rpc_chat_msg.rpc_id(other, "[Proche] " + who, text)
					rpc_bubble.rpc_id(other, id, text)


@rpc("authority", "reliable")
func rpc_bubble(sender: int, text: String) -> void:
	var who: String = roster.get(sender, {}).get("pseudo", "")
	if who != "" and is_blocked(who):
		return
	bubble.emit(sender, text)


## Voix : relayée aux joueurs proches (« local ») ou aux membres du groupe (« group »).
## Canal de transfert 2 : la voix ne retarde jamais les positions des joueurs.
@rpc("any_peer", "unreliable_ordered", "call_remote", 2)
func rpc_voice(data: PackedByteArray, channel: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _sessions.has(id) or data.size() > VOICE_MAX_BYTES or data.is_empty():
		return
	if channel == "group":
		var g: String = social.group_of(_sessions[id])
		if g == "":
			return
		for other in _sessions:
			if other != id and social.group_of(_sessions[other]) == g:
				rpc_voice_in.rpc_id(other, id, data, "group")
		return
	var me: Vector3 = _pos.get(id, Vector3(INF, 0, INF))
	for other in _sessions:
		if other == id:
			continue
		var p: Vector3 = _pos.get(other, Vector3(INF, 0, INF))
		if Vector2(p.x - me.x, p.z - me.z).length() < VOICE_RANGE:
			rpc_voice_in.rpc_id(other, id, data, "local")


@rpc("authority", "unreliable_ordered", "call_remote", 2)
func rpc_voice_in(sender: int, data: PackedByteArray, channel: String) -> void:
	var who: String = roster.get(sender, {}).get("pseudo", "")
	if who != "" and is_blocked(who):
		return
	voice_received.emit(sender, data, channel)


func send_voice(data: PackedByteArray, channel: String) -> void:
	if online and not data.is_empty():
		rpc_voice.rpc_id(1, data.slice(0, VOICE_MAX_BYTES), channel)


func _broadcast_chat(from: String, text: String) -> void:
	for id in _sessions:
		rpc_chat_msg.rpc_id(id, from, text)


# --- Modération & Sécurité Joueurs (Apple App Store Guideline 1.2) ------------

func load_blocked_players() -> void:
	if FileAccess.file_exists(BLOCKED_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(BLOCKED_PATH))
		if d is Dictionary:
			blocked_players = d


func save_blocked_players() -> void:
	var f := FileAccess.open(BLOCKED_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(blocked_players))


func is_blocked(player_name: String) -> bool:
	return blocked_players.has(player_name.strip_edges().to_lower())


func block_player(player_name: String) -> void:
	var key := player_name.strip_edges().to_lower()
	if key != "" and key != pseudo.to_lower():
		blocked_players[key] = true
		save_blocked_players()


func unblock_player(player_name: String) -> void:
	var key := player_name.strip_edges().to_lower()
	if blocked_players.has(key):
		blocked_players.erase(key)
		save_blocked_players()


func report_player(target_pseudo: String, reason: String) -> void:
	if online:
		rpc_report_player.rpc_id(1, target_pseudo, reason)


@rpc("any_peer", "reliable")
func rpc_report_player(target_pseudo: String, reason: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var reporter: String = str(_sessions.get(id, "Inconnu"))
	print("[MODÉRATION] %s a signalé %s pour : %s" % [reporter, target_pseudo, reason])
	var entry := {
		"from": reporter,
		"target": target_pseudo,
		"reason": reason,
		"date": Time.get_datetime_string_from_system()
	}
	var reports: Array = []
	if FileAccess.file_exists(REPORTS_LOG):
		var d = JSON.parse_string(FileAccess.get_file_as_string(REPORTS_LOG))
		if d is Array:
			reports = d
	reports.append(entry)
	if reports.size() > 500:
		reports.pop_front()
	var f := FileAccess.open(REPORTS_LOG, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(reports))
	rpc_notice.rpc_id(id, "Signalement envoyé. Merci de contribuer au respect de la communauté !")


func _server_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_clock += delta
	social.server_tick(delta)
	city.server_tick(delta)
	lutte.server_tick(delta)
	if _traffic:
		# Les joueurs hors de la carte (Arène de Pikine) n'ont pas de trafic autour d'eux
		var in_city: Array = []
		for p in _pos.values():
			if _traffic.city.bounds.has_point(Vector2(p.x, p.z)):
				in_city.append(p)
		var tt := Time.get_ticks_usec()
		_traffic.tick(delta, in_city)
		_prof["trafic"] += Time.get_ticks_usec() - tt
	_send_t -= delta
	if _send_t <= 0.0:
		_tick_frame += 1
		# Cadence adaptée au nombre de joueurs (les clients lissent les mouvements)
		var n := _sessions.size()
		_send_t = SEND_RATE if n <= 100 else (0.12 if n <= 500 else 0.16)
		var tp := Time.get_ticks_usec()
		_rebuild_grid()
		_cell_snap.clear()
		for id in _sessions:
			if _pos.has(id):
				var snap: Array = _snapshot_for(id)
				rpc_snapshot.rpc_id(id, snap[0], snap[1])
		_prof["joueurs"] += Time.get_ticks_usec() - tp
	# Trafic : 5 fois par seconde suffisent (les clients lissent les trajectoires)
	_traffic_t -= delta
	if _traffic and _traffic_t <= 0.0:
		_traffic_t = 0.2
		var tv := Time.get_ticks_usec()
		_traffic.rebuild_grid()
		_traffic.begin_send()
		for id in _sessions:
			if _pos.has(id):
				rpc_traffic.rpc_id(id, _traffic.snapshot_for(_pos[id]))
		_prof["voitures"] += Time.get_ticks_usec() - tv
	_time_t -= delta
	if _time_t <= 0.0:
		_time_t = 10.0
		for id in _sessions:
			rpc_world_time.rpc_id(id, GameState.game_minutes, _clock)
	# Liste des joueurs : un seul message groupé par seconde pour tout le monde
	_delta_t -= delta
	if _delta_t <= 0.0:
		_delta_t = 1.0
		if not _delta_add.is_empty() or not _delta_remove.is_empty() or not _delta_job.is_empty() or not _delta_tenue.is_empty():
			var pack := {"add": _delta_add, "remove": _delta_remove, "job": _delta_job, "tenue": _delta_tenue}
			for other in _sessions:
				rpc_roster_delta.rpc_id(other, pack)
			_delta_add = {}
			_delta_remove = []
			_delta_job = {}
			_delta_tenue = {}
	_pay_t -= delta
	if _pay_t <= 0.0:
		_pay_t = _pay_every
		for id in _states:
			var job: String = _states[id].get("job", "")
			if SALARY.has(job):
				rpc_receive_money.rpc_id(id, "Serveur", SALARY[job], "Salaire de %s" % JOBS[job].to_lower())
			elif Factions.FACTIONS.has(job) and _sessions.has(id):
				var xp := faction_xp(id, job)
				var pay := Factions.salary(job, xp)
				if pay > 0:
					rpc_receive_money.rpc_id(id, "Serveur", pay, "Salaire : %s (%s)" % [Factions.FACTIONS[job]["name"], Factions.rank_name(job, xp)])
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 15.0
		if _dirty:
			var t_save := Time.get_ticks_usec()
			_save_accounts()
			_prof["sauvegarde"] += Time.get_ticks_usec() - t_save
	# Statistiques du serveur (journal) toutes les 10 s
	var us := Time.get_ticks_usec() - t0
	_stats_us += us
	_stats_max = maxi(_stats_max, us)
	_stats_frames += 1
	_stats_t -= delta
	if _stats_t <= 0.0:
		_stats_t = 10.0
		var sent := 0
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet and enet.host:
			sent = enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
		print("STATS joueurs=%d voitures=%d calcul moyen=%.2f ms max=%.2f ms envoi=%.1f ko/s images/s=%d | par seconde : trafic %.0f ms, joueurs %.0f ms, envoi voitures %.0f ms, états reçus %.0f ms" % [
			_sessions.size(), _traffic.cars.size() if _traffic else 0, _stats_us / 1000.0 / maxi(1, _stats_frames), _stats_max / 1000.0, sent / 10240.0,
			_stats_frames / 10, _prof["trafic"] / 10000.0, _prof["joueurs"] / 10000.0, _prof["voitures"] / 10000.0, _prof["etats"] / 10000.0])
		print("      connexions %.0f ms, sauvegarde des comptes %.0f ms (sur 10 s), temps d'image Godot %.1f ms" % [_prof["connexions"] / 1000.0, _prof["sauvegarde"] / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
		for k in _prof:
			_prof[k] = 0
		_stats_us = 0
		_stats_max = 0
		_stats_frames = 0


## Grille des joueurs (cellules de CELL mètres) pour trouver vite les voisins
func _rebuild_grid() -> void:
	_grid.clear()
	_enc.clear()
	for id in _pos:
		var p: Vector3 = _pos[id]
		var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not _grid.has(c):
			_grid[c] = PackedInt32Array()
		_grid[c].append(id)
		var st: Dictionary = _states[id]
		_enc[id] = PackedInt32Array([id, roundi(st["x"] * 10.0), roundi(st["y"] * 10.0), roundi(st["z"] * 10.0),
			roundi(st["r"] * 100.0), roundi(st["sp"] * 10.0), int(st["w"]) | (int(st["wl"]) << 1), VEH.find(st["v"])])


## Joueurs proches de la cellule de `id` : [PackedInt32Array (STRIDE entiers par joueur), policiers [[id, liste]]]
## Le même instantané sert à tous les joueurs de la cellule (le client ignore sa propre entrée).
func _snapshot_for(id: int) -> Array:
	var me: Vector3 = _pos[id]
	var c := Vector2i(floori(me.x / CELL), floori(me.z / CELL))
	if _cell_snap.has(c):
		return _cell_snap[c]
	if _rings.is_empty():
		var rr := int(ceil(AOI / CELL))
		for dx in range(-rr, rr + 1):
			for dz in range(-rr, rr + 1):
				var dd := Vector2(dx, dz).length() * CELL
				if dd <= AOI + CELL * 0.5:
					_rings.append([dd, Vector2i(dx, dz)])
		_rings.sort_custom(func(a, b): return a[0] < b[0])
	# Cellules les plus proches d'abord avec filtrage LOD par distance
	var data := PackedInt32Array()
	var pols: Array = []
	var n := 0
	for ring in _rings:
		if n >= AOI_MAX:
			break
		var dist: float = ring[0]
		# Network LOD : les cellules moyennes/lointaines ne sont envoyées qu'à cadence réduite
		if dist > LOD_MID and (_tick_frame % 2 != 0):
			continue
		if dist > LOD_FAR and (_tick_frame % 4 != 0):
			continue
		for other in _grid.get(c + ring[1], PackedInt32Array()):
			if _enc.has(other):
				data.append_array(_enc[other])
				var pol: Array = _states[other].get("pol", [])
				if not pol.is_empty():
					pols.append([other, pol])
				n += 1
				if n >= AOI_MAX:
					break
	var snap := [data, pols]
	_cell_snap[c] = snap
	return snap


# --- Client ------------------------------------------------------------------------------

func connect_and_login(host: String, who: String, password: String, wanted_avatar: String, create: bool, port: int = PORT) -> void:
	disconnect_from_server()
	_pending_login = {"pseudo": who.strip_edges(), "password": password, "avatar": wanted_avatar, "create": create}
	var target_host := host.strip_edges()
	if target_host == "":
		target_host = DEFAULT_HOST
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(target_host, port)
	if err != OK:
		# Résolution DNS/IPv6 via le singleton IP de Godot pour la conformité Apple App Store (NAT64/DNS64)
		var resolved := IP.resolve_hostname(target_host, IP.TYPE_ANY)
		if resolved != "" and resolved != target_host:
			err = peer.create_client(resolved, port)
	if err != OK:
		_fail("Adresse de serveur invalide ou introuvable.")
		return
	multiplayer.multiplayer_peer = peer
	connection_changed.emit("Connexion à %s:%d..." % [target_host, port])


func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer != null and not is_server:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	online = false
	remote.clear()
	roster.clear()


func start_offline(p_pseudo: String = "", p_avatar: String = "heros") -> void:
	disconnect_from_server()
	online = false
	pseudo = p_pseudo.strip_edges() if p_pseudo.strip_edges() != "" else "Galsenois"
	avatar = p_avatar if p_avatar != "" else "heros"
	friend_code = generate_friend_code(pseudo)
	GameState.load_game()


func _on_connected() -> void:
	_patient(1)
	connection_changed.emit("Connecté, identification...")


func _fail(msg: String) -> void:
	if is_server:
		return
	var was_online := online
	online = false
	remote.clear()
	_pending_login = {}
	multiplayer.multiplayer_peer = null
	connection_changed.emit(msg)
	if was_online:
		GameState.notify.emit("Hors ligne : " + msg)
	else:
		login_result.emit(false, msg)


@rpc("authority", "reliable")
func rpc_login_result(ok: bool, message: String, save: Dictionary, server_avatar: String) -> void:
	if ok:
		online = true
		pseudo = _pending_login.get("pseudo", "")
		avatar = server_avatar
		friend_code = generate_friend_code(pseudo)
		GameState.start_online(save)
		emotes.hello()
		factions.hello()
		properties.hello()
		trade.hello()
		foot.hello()
		city.hello()
	_pending_login = {}
	login_result.emit(ok, message)


@rpc("authority", "unreliable_ordered")
func rpc_snapshot(data: PackedInt32Array, pols: Array) -> void:
	received += 1
	if light:
		return
	var seen := {}
	var pol_of := {}
	for pe in pols:
		pol_of[int(pe[0])] = pe[1]
	for k in range(0, data.size() - STRIDE + 1, STRIDE):
		var id: int = data[k]
		if not roster.has(id):
			continue # soi-même ou joueur pas encore annoncé
		seen[id] = true
		var info: Dictionary = roster[id]
		var flags: int = data[k + 6]
		var vi: int = data[k + 7]
		var st := {"x": data[k + 1] / 10.0, "y": data[k + 2] / 10.0, "z": data[k + 3] / 10.0, "r": data[k + 4] / 100.0,
			"sp": data[k + 5] / 10.0, "v": VEH[vi] if vi > 0 and vi < VEH.size() else "", "w": flags & 1, "wl": flags >> 1,
			"job": info["job"], "pol": pol_of.get(id, [])}
		if not remote.has(id):
			remote[id] = {"pseudo": info["pseudo"], "avatar": info["avatar"], "tenue": info.get("tenue", ""), "state": st, "t": Time.get_ticks_msec()}
		else:
			remote[id]["state"] = st
			remote[id]["avatar"] = info["avatar"]
			remote[id]["tenue"] = info.get("tenue", "")
			remote[id]["t"] = Time.get_ticks_msec()
	for id in remote.keys():
		if not seen.has(id):
			remote.erase(id)


# --- Liste de tous les joueurs (petits messages, seulement quand elle change) ---

@rpc("authority", "reliable")
func rpc_roster_full(full: Dictionary) -> void:
	roster.clear()
	for id in full:
		var e: Array = full[id]
		roster[int(id)] = {"pseudo": e[0], "avatar": e[1], "job": e[2], "wl": e[3], "tenue": str(e[4]) if e.size() > 4 else ""}
	roster.erase(multiplayer.get_unique_id())


## Changements groupés : {add: {id: [pseudo, avatar, tenue]}, remove: [id], job: {id: [métier, étoiles]}, tenue: {id: tenue}}
@rpc("authority", "reliable")
func rpc_roster_delta(pack: Dictionary) -> void:
	var me := multiplayer.get_unique_id()
	var add: Dictionary = pack.get("add", {})
	for id in add:
		if int(id) != me:
			roster[int(id)] = {"pseudo": add[id][0], "avatar": add[id][1], "job": "", "wl": 0, "tenue": str(add[id][2]) if add[id].size() > 2 else ""}
	for id in pack.get("remove", []):
		roster.erase(int(id))
		remote.erase(int(id))
	var jobs: Dictionary = pack.get("job", {})
	for id in jobs:
		if roster.has(int(id)):
			roster[int(id)]["job"] = jobs[id][0]
			roster[int(id)]["wl"] = jobs[id][1]
	var tenues: Dictionary = pack.get("tenue", {})
	for id in tenues:
		if roster.has(int(id)):
			roster[int(id)]["tenue"] = str(tenues[id])


@rpc("authority", "reliable")
func rpc_chat_msg(from: String, text: String) -> void:
	for b in blocked_players:
		if from.to_lower().contains(b):
			return
	chat_received.emit(from, text)


@rpc("authority", "reliable")
func rpc_world_time(minutes: float, clock_s: float) -> void:
	server_time = minutes
	GameState.game_minutes = minutes
	_clock_base = clock_s
	_clock_at = Time.get_ticks_msec()


## Horloge commune à tous les joueurs (secondes depuis le démarrage du serveur)
func clock() -> float:
	if is_server:
		return _clock
	return _clock_base + (Time.get_ticks_msec() - _clock_at) / 1000.0


@rpc("authority", "unreliable_ordered")
func rpc_traffic(cars: PackedInt32Array) -> void:
	if light:
		return
	traffic_received.emit(cars)


@rpc("any_peer", "reliable")
func rpc_claim_car(id: int) -> void:
	if is_server and _sessions.has(multiplayer.get_remote_sender_id()) and _traffic:
		_traffic.claim(id)


@rpc("any_peer", "reliable")
func rpc_give(target: int, amount: int, reason: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _sessions.has(id) and _sessions.has(target) and amount > 0 and amount <= 1000000:
		rpc_receive_money.rpc_id(target, _sessions[id], amount, reason.left(60))


@rpc("authority", "reliable")
func rpc_receive_money(from: String, amount: int, reason: String) -> void:
	money_received.emit(from, amount, reason)
	if reason == "":
		GameState.add_money(amount, "Envoyé par %s" % from)
	else:
		GameState.add_money(amount, reason if from == "Serveur" else "%s (%s)" % [reason, from])


## Appel d'un service (taxi, police) : prévient tous les joueurs en service de ce métier.
@rpc("any_peer", "reliable")
func rpc_call_service(kind: String) -> void:
	if not is_server or not JOBS.has(kind):
		return
	var id := multiplayer.get_remote_sender_id()
	if not _sessions.has(id) or not _states.has(id):
		return
	var st: Dictionary = _states[id]
	var reached := 0
	for other in _states:
		if other != id and _states[other].get("job", "") == kind:
			reached += 1
			var text: String = {"taxi": "%s demande un taxi !", "samu": "%s appelle le SAMU !", "gang": "%s cherche le gang...", "mecanicien": "%s a besoin d'un mécanicien !"}.get(kind, "%s appelle la police !") % _sessions[id]
			rpc_job_target.rpc_id(other, text, st.get("x", 0.0), st.get("z", 0.0))
	if reached == 0:
		rpc_notice.rpc_id(id, "Aucun joueur %s en service pour le moment." % JOBS[kind].to_lower())
	else:
		rpc_notice.rpc_id(id, "%d %s prévenu(s), il arrive." % [reached, JOBS[kind].to_lower()])


## Course de taxi entre joueurs : le passager annonce sa destination au chauffeur.
@rpc("any_peer", "reliable")
func rpc_fare(driver: int, dest: String, price: int, x: float, z: float) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _sessions.has(id) and _sessions.has(driver):
		rpc_job_target.rpc_id(driver, "%s : « %s, s'il te plaît » (%d FCFA à l'arrivée)" % [_sessions[id], dest.left(40), price], x, z)


@rpc("authority", "reliable")
func rpc_job_target(text: String, x: float, z: float) -> void:
	job_target.emit(text, Vector3(x, 0, z))


## Un joueur policier arrête un joueur recherché (le serveur vérifie le métier, les étoiles et la distance).
@rpc("any_peer", "reliable")
func rpc_arrest(target: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _states.has(id) or not _states.has(target) or not _sessions.has(target):
		return
	var a: Dictionary = _states[id]
	var b: Dictionary = _states[target]
	var stars: int = int(b.get("wl", 0))
	var d := Vector2(a.get("x", 0.0) - b.get("x", 0.0), a.get("z", 0.0) - b.get("z", 0.0)).length()
	if a.get("job", "") != "police" or stars <= 0 or d > 8.0:
		rpc_notice.rpc_id(id, "Arrestation impossible.")
		return
	rpc_arrested.rpc_id(target, _sessions[id])
	factions.reward(id, stars, 1000 * stars, "Prime d'arrestation de %s" % _sessions[target])
	_broadcast_chat("Serveur", "%s a été arrêté par l'agent %s." % [_sessions[target], _sessions[id]])


@rpc("authority", "reliable")
func rpc_arrested(cop: String) -> void:
	arrested.emit(cop)


@rpc("any_peer", "reliable")
func rpc_ride(driver: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _sessions.has(id) and _sessions.has(driver):
		rpc_notice.rpc_id(driver, "%s est monté dans ta voiture." % _sessions[id])


## SMS privé entre joueurs (le destinataire doit être connecté)
@rpc("any_peer", "reliable")
func rpc_sms(to: String, text: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _sessions.has(id):
		return
	for other in _sessions:
		if _sessions[other] == to:
			rpc_sms_in.rpc_id(other, _sessions[id], text.strip_edges().left(200))
			return
	rpc_notice.rpc_id(id, "%s n'est pas connecté : SMS non distribué." % to)


@rpc("authority", "reliable")
func rpc_sms_in(from: String, text: String) -> void:
	sms_received.emit(from, text)


@rpc("authority", "reliable")
func rpc_notice(text: String) -> void:
	GameState.notify.emit(text)


## Événements de missions (synchronisation multijoueur et solo en ligne)
@rpc("any_peer", "reliable")
func rpc_mission_event(event_type: String, mission_id: String, mission_title: String, reward: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _sessions.has(id):
		return
	var who: String = _sessions[id]
	if event_type == "start":
		print("[Mission Serveur] %s a lancé la mission : %s" % [who, mission_title])
	elif event_type == "complete":
		print("[Mission Serveur] %s a accompli la mission : %s (+%d FCFA)" % [who, mission_title, reward])
		_broadcast_chat("Serveur", "🏆 Félicitations à %s pour avoir triomphé dans la mission « %s » (+%s) !" % [who, mission_title, GameState.fcfa(reward)])


func send_mission_event(event_type: String, mission_id: String, mission_title: String, reward: int = 0) -> void:
	if online:
		rpc_mission_event.rpc_id(1, event_type, mission_id, mission_title, reward)


## Rejoindre un ami grâce à son Code Ami unique (ex: "GAL-12345")
## Note : géré côté client pour compatibilité totale avec le serveur dédié officiel
func join_by_friend_code(code: String) -> void:
	var clean := code.strip_edges().to_upper()
	if clean == "":
		GameState.notify.emit("Entre un code ami.")
		return
	if not clean.begins_with("GAL-") and not "-" in clean:
		clean = "GAL-" + clean
	if not online:
		pending_friend_join_code = clean
		GameState.notify.emit("Code mémorisé. Connecte-toi pour rejoindre ton ami !")
		return

	# Recherche de l'ami dans les joueurs en ligne (roster)
	var found_peer := -1
	var found_name := ""
	for pid in roster:
		var p_name: String = str(roster[pid].get("pseudo", ""))
		if generate_friend_code(p_name) == clean:
			found_peer = pid
			found_name = p_name
			break

	if found_peer < 0:
		friend_joined.emit(false, "Ce joueur n'est pas connecté à Dakar pour l'instant.", "", Vector3.ZERO, -1, clean)
		GameState.notify.emit("Ami non trouvé ou hors ligne pour le code %s" % clean)
		return

	var pos := Vector3.ZERO
	if remote.has(found_peer) and remote[found_peer].has("state"):
		var st: Dictionary = remote[found_peer]["state"]
		pos = Vector3(float(st.get("x", 0.0)), float(st.get("y", 0.0)), float(st.get("z", 0.0)))

	save_friend(found_name, clean)
	friend_joined.emit(true, "Ami trouvé : %s est à Dakar !" % found_name, found_name, pos, found_peer, clean)
	GameState.notify.emit("🤝 Tu as rejoint %s !" % found_name)


static func generate_friend_code(who: String) -> String:
	var h := absi(who.strip_edges().to_lower().hash())
	return "GAL-%05d" % (10000 + (h % 90000))


func get_my_friend_code() -> String:
	if friend_code != "":
		return friend_code
	if pseudo != "":
		return generate_friend_code(pseudo)
	return generate_friend_code(GameState.player_name if GameState.player_name != "" else "Joueur")


func load_saved_friends() -> void:
	if FileAccess.file_exists(FRIENDS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(FRIENDS_PATH))
		if d is Array:
			saved_friends = d


func save_friends_file() -> void:
	var f := FileAccess.open(FRIENDS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(saved_friends))


func save_friend(who: String, code: String) -> void:
	who = who.strip_edges()
	code = code.strip_edges().to_upper()
	if who == "":
		return
	for f in saved_friends:
		if f is Dictionary and (f.get("pseudo", "").to_lower() == who.to_lower() or f.get("code", "") == code):
			f["pseudo"] = who
			f["code"] = code
			f["last_seen"] = int(Time.get_unix_time_from_system())
			save_friends_file()
			return
	saved_friends.append({"pseudo": who, "code": code, "last_seen": int(Time.get_unix_time_from_system())})
	save_friends_file()


func remove_saved_friend(code: String) -> void:
	code = code.strip_edges().to_upper()
	for i in range(saved_friends.size() - 1, -1, -1):
		var f = saved_friends[i]
		if f is Dictionary and (f.get("code", "") == code or f.get("pseudo", "").to_lower() == code.to_lower()):
			saved_friends.remove_at(i)
	save_friends_file()


func claim_car(id: int) -> void:
	if online:
		rpc_claim_car.rpc_id(1, id)


## Donne de l'argent à un autre joueur (identifiant de pair)
func give_money(target: int, amount: int, reason := "") -> bool:
	if not online or not GameState.spend(amount):
		return false
	rpc_give.rpc_id(1, target, amount, reason)
	return true


func send_sms(to: String, text: String) -> void:
	if online and text.strip_edges() != "":
		rpc_sms.rpc_id(1, to, text)


## Identifiant de pair d'un joueur connecté (ou -1)
func peer_of(who: String) -> int:
	for id in roster:
		if roster[id]["pseudo"] == who:
			return id
	return -1


func call_service(kind: String) -> void:
	if online:
		rpc_call_service.rpc_id(1, kind)


func send_fare(driver: int, dest: String, price: int, pos: Vector3) -> void:
	if online:
		rpc_fare.rpc_id(1, driver, dest, price, pos.x, pos.z)


func arrest(target: int) -> void:
	if online:
		rpc_arrest.rpc_id(1, target)


func notify_ride(driver: int) -> void:
	if online:
		rpc_ride.rpc_id(1, driver)


## Envoi : par défaut aux joueurs proches ; « /t texte » à tout Dakar ; « /g texte » à son groupe
func send_chat(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	if not online:
		var p_name: String = pseudo if pseudo != "" else "Moi"
		chat_received.emit("[Proche] " + p_name, text)
		bubble.emit(1, text)
		_npc_chat_reply(text)
		return
	var channel := "local"
	if text.begins_with("/t ") or text.begins_with("/a "):
		channel = "all"
		text = text.substr(3)
	elif text.begins_with("/g "):
		channel = "group"
		text = text.substr(3)
	elif text.begins_with("/f "):
		channel = "faction"
		text = text.substr(3)
	rpc_chat.rpc_id(1, text, channel)


func _npc_chat_reply(text: String) -> void:
	var lower := text.to_lower()
	var reply := ""
	if "salam" in lower or "bonjour" in lower or "salut" in lower:
		reply = "Malekum salam ! Nanga def ?"
	elif "stade" in lower or "foot" in lower or "match" in lower:
		reply = "Le grand match se joue au Stade Iba Mar Diop en Médina !"
	elif "lutte" in lower or "arene" in lower or "arène" in lower:
		reply = "L'Arène nationale est à Pikine, de grands combats s'y préparent !"
	elif "taxi" in lower:
		reply = "Hèle un taxi jaune et noir sur la route, ils s'arrêtent partout !"
	elif "brt" in lower or "bus" in lower:
		reply = "Le SunuBRT électrique dessert la Ligne 1 jusqu'à Guédiawaye !"
	elif "ter" in lower or "train" in lower:
		reply = "Le TER part de la Gare de Dakar vers Diamniadio toutes les 15 minutes !"
	elif "merci" in lower or "sant" in lower:
		reply = "Diereudieuf ! Bonne journée à Dakar."
	elif "comment" in lower or "ou" in lower or "où" in lower:
		reply = "Regarde sur la carte ou ton téléphone pour trouver ton chemin !"
	else:
		var generic_replies := [
			"Alhamdoulillah, la vie est belle à Dakar !",
			"Waaw kay, bienvenue dans le quartier !",
			"Sant Yalla, tout va bien ici !",
			"Prends soin de toi l'ami !",
		]
		reply = generic_replies[randi() % generic_replies.size()]

	get_tree().create_timer(randf_range(1.2, 2.0)).timeout.connect(func():
		chat_received.emit("[Proche] Passant dakarois", reply)
	)


func send_save(save: Dictionary) -> void:
	if online:
		rpc_save.rpc_id(1, save)


func send_state(state: Dictionary) -> void:
	if not online:
		return
	var a := [snappedf(state["x"], 0.05), snappedf(state["y"], 0.05), snappedf(state["z"], 0.05), snappedf(state["r"], 0.02),
		snappedf(state["sp"], 0.1), state.get("v", ""), state.get("w", 0), state.get("wl", 0), state.get("job", ""), state.get("pol", [])]
	var now := Time.get_ticks_msec() / 1000.0
	if a == _last_sent and now - _last_sent_t < HEARTBEAT:
		return
	_last_sent = a
	_last_sent_t = now
	rpc_state.rpc_id(1, a)


func players_online() -> int:
	return roster.size() + (1 if online else 0)


func _process(delta: float) -> void:
	if is_server:
		_server_process(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_server and _dirty:
		_save_accounts()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_server:
		social.save_groups()


# --- Utilitaires ---------------------------------------------------------------------------

static func _sha(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _key_hash(who: String, password: String) -> String:
	return _sha("galsen-life|" + who.strip_edges().to_lower() + "|" + password)
